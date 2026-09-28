namespace Dc.Webxdc {

    /* One lease on core's per-profile, per-message gossip channel. Calls must
       finish before leave, including when a window is immediately reopened:
       core executes JSON-RPC requests concurrently. This class owns no view. */
    public class RealtimeSession : Object {
        public const int MAX_DATA = 128000;
        private const int MAX_QUEUED_BYTES = 1024000;
        private static List<RealtimeSession> sessions;
        private RpcClient rpc;
        private int account_id;
        private int msg_id;
        private RealtimeSession? previous;
        private Queue<Bytes> outgoing = new Queue<Bytes> ();
        private size_t queued_bytes = 0;
        private string? token = null;
        private string? core_token = null;
        private bool leave_pending = false;
        private bool busy = false;
        private bool closed = false;
        public bool finished { get; private set; default = false; }

        public signal void data_received (string token, Json.Array data);
        public signal void channel_failed (string token, string message);
        private signal void completed ();

        public RealtimeSession (RpcClient rpc, int account_id, int msg_id) {
            this.rpc = rpc;
            this.account_id = account_id;
            this.msg_id = msg_id;
            previous = find (rpc, account_id, msg_id);
            if (previous != null) previous.close ();
            sessions.prepend (this);
        }

        private static RealtimeSession? find (RpcClient rpc, int account_id,
                                              int msg_id) {
            foreach (var session in sessions) {
                if (session.rpc == rpc && session.account_id == account_id
                        && session.msg_id == msg_id) return session;
            }
            return null;
        }

        public bool join (string id) {
            if (closed || token != null || id.length == 0 || id.length > 128)
                return false;
            token = id;
            pump ();
            return true;
        }

        /* Validate again at the native boundary: page code can bypass the JS
           API and post arbitrary JSON to the platform message handler. */
        public static Bytes? parse_data (Json.Node? node) {
            if (node == null || node.get_node_type () != Json.NodeType.ARRAY)
                return null;
            var arr = node.get_array ();
            if (arr.get_length () > MAX_DATA) return null;
            var bytes = new uint8[arr.get_length ()];
            for (uint i = 0; i < arr.get_length (); i++) {
                var item = arr.get_element (i);
                if (item.get_node_type () != Json.NodeType.VALUE
                        || item.get_value_type () != typeof (int64)) return null;
                int64 value = item.get_int ();
                if (value < 0 || value > 255) return null;
                bytes[i] = (uint8) value;
            }
            return new Bytes (bytes);
        }

        public bool send (string id, Json.Node? data) {
            if (closed || token == null || token != id) return false;
            var bytes = parse_data (data);
            if (bytes == null || outgoing.length >= 64
                    || queued_bytes + bytes.get_size () > MAX_QUEUED_BYTES)
                return false;
            outgoing.push_tail (bytes);
            queued_bytes += bytes.get_size ();
            pump ();
            return true;
        }

        public void leave (string id) {
            if (token == null || token != id) return;
            token = null;
            // Replacing the owning queue also releases each queued Bytes.
            outgoing = new Queue<Bytes> ();
            queued_bytes = 0;
            if (core_token != null) leave_pending = true;
            pump ();
        }

        public void close () {
            if (closed) return;
            closed = true;
            if (token != null) leave (token);
            else pump ();
        }

        private void pump () {
            if (!busy && !finished) drain.begin ();
        }

        private async void drain () {
            busy = true;
            if (previous != null) {
                if (!previous.finished) {
                    ulong handler = previous.completed.connect (() => { drain.callback (); });
                    yield;
                    previous.disconnect (handler);
                }
                previous = null;
            }
            while (leave_pending || (!closed && token != null)) {
                string method;
                string? sending_token = token;
                var args = Params.begin ().add_int (account_id).add_int (msg_id);
                if (leave_pending) {
                    method = "leave_webxdc_realtime";
                    leave_pending = false;
                    core_token = null;
                } else if (core_token != token) {
                    method = "send_webxdc_realtime_advertisement";
                    core_token = token;
                } else if (!outgoing.is_empty ()) {
                    method = "send_webxdc_realtime_data";
                    var bytes = outgoing.pop_head ();
                    queued_bytes -= bytes.get_size ();
                    var data = new Json.Array ();
                    foreach (uint8 byte in bytes.get_data ()) data.add_int_element (byte);
                    args.add_json_array (data);
                } else {
                    break;
                }
                try {
                    yield rpc.call (method, args.build ());
                } catch (Error e) {
                    debug ("webxdc realtime %s: %s", method, e.message);
                    if (method == "send_webxdc_realtime_advertisement"
                            && token != null && token == sending_token) {
                        leave (token);
                        channel_failed (sending_token, e.message);
                    }
                }
            }
            busy = false;
            if (closed) {
                finished = true;
                sessions.remove (this);
                completed ();
            }
        }

        public static bool route_event (RpcClient rpc, int account_id,
                                         string kind, Json.Object event) {
            int msg_id = (int) json_int (event, "msgId");
            var session = find (rpc, account_id, msg_id);
            if (session == null || session.closed || session.token == null)
                return false;
            if (session.leave_pending || session.core_token != session.token)
                return false;
            if (kind == "WebxdcRealtimeData") {
                var node = event.get_member ("data");
                if (parse_data (node) == null) return false;
                session.data_received (session.token, node.get_array ());
                return true;
            }
            /* Core adds advertised peers to an already joined channel. Do
               not reply with another advertisement (which creates a loop),
               or join an app that has not requested realtime / has left. */
            return kind == "WebxdcRealtimeAdvertisementReceived";
        }
    }
}
