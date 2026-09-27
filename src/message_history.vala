namespace Dc {

    public class MessageHistory : Object {

        public static void context_range (Json.Array ids, uint target,
                                           out uint start, out uint end) {
            start = target > 30 ? target - 30 : 0;
            end = uint.min (target + 31, ids.get_length ());
        }

        public static uint initial_batch_start (Json.Array ids, int first_unread,
                                                uint batch_size = 30) {
            uint start = ids.get_length () > batch_size
                ? ids.get_length () - batch_size : 0;
            int unread_index = find_id (ids, first_unread);
            /* Include one preceding row so the divider has context and
               scrolling up can reach the earlier-history loading threshold. */
            return unread_index >= 0
                ? uint.min (start, (uint) int.max (0, unread_index - 1)) : start;
        }

        public static int find_id (Json.Array ids, int message_id) {
            for (uint i = 0; i < ids.get_length (); i++) {
                if ((int) ids.get_int_element (i) == message_id) return (int) i;
            }
            return -1;
        }

    }
}
