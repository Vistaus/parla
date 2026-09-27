namespace Dc {

    /* One query lifetime for both search surfaces. Invalidate immediately on
       edits (not after the debounce), and retain the originating profile. */
    public class MessageSearch : Object {
        private RpcClient? rpc;
        private uint timer = 0;
        public uint generation { get; private set; }
        public int account_id { get; private set; }
        public int[] ids = {};
        public string query { get; private set; default = ""; }
        public bool busy { get; private set; }
        public string? error_message { get; private set; }
        public signal void changed ();

        public MessageSearch (RpcClient? rpc = null) { this.rpc = rpc; }

        public void set_rpc (RpcClient rpc) {
            cancel ();
            this.rpc = rpc;
        }

        public static string snippet (string text, string query) {
            string lower = text.down ();
            int match = lower.index_of (query.down ());
            int start = match >= 0 ? int.max (0, lower.char_count (match) - 50) : 0;
            int count = text.char_count ();
            start = int.min (start, count);
            int end = int.min (count, start + 240);
            int first_byte = text.index_of_nth_char (start);
            string excerpt = text.substring (first_byte, text.index_of_nth_char (end) - first_byte);
            return (start > 0 ? "…" : "") + excerpt.replace ("\n", " ")
                + (end < count ? "…" : "");
        }

        public void cancel () {
            generation++;
            if (timer != 0) Source.remove (timer);
            timer = 0;
            ids = {};
            query = "";
            busy = false;
            error_message = null;
        }

        public bool is_current (uint token) {
            return rpc != null && token == generation && account_id == rpc.account_id;
        }

        public void submit (string text, int chat_id = 0) {
            cancel ();
            account_id = rpc != null ? rpc.account_id : 0;
            query = text.strip ();
            busy = query != "" && account_id > 0;
            changed ();
            if (!busy) return;
            uint token = generation;
            timer = Timeout.add (200, () => {
                timer = 0;
                run.begin (token, chat_id);
                return Source.REMOVE;
            });
        }

        private async void run (uint token, int chat_id) {
            try {
                var matches = yield rpc.search_messages (account_id, query, chat_id);
                if (!is_current (token)) return;
                ids = matches;
            } catch (Error e) {
                if (!is_current (token)) return;
                error_message = e.message;
            }
            busy = false;
            changed ();
        }
    }
}
