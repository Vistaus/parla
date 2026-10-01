namespace Dc {

    public class SearchResultsView : Gtk.Box {
        private RpcClient? rpc;
        public MessageSearch search { get; private set; }
        private Gtk.Label scope;
        private Gtk.Label status;
        private Gtk.ListBox list;
        private Gtk.Button more;
        private int loaded = 0;
        private bool loading = false;
        private int scope_account = 0;
        private HashTable<string, Gdk.Texture> avatar_images =
            new HashTable<string, Gdk.Texture> (str_hash, str_equal);
        public signal void message_activated (int account_id, int chat_id, int message_id);

        public SearchResultsView () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 6);
            visible = false;
            search = new MessageSearch ();
            scope = new Gtk.Label (_("Messages in selected profile"));
            scope.wrap = true;
            scope.add_css_class ("dim-label");
            append (scope);
            status = new Gtk.Label (_("Type to search messages"));
            status.wrap = true;
            status.margin_start = status.margin_end = 8;
            append (status);
            list = new Gtk.ListBox ();
            list.selection_mode = Gtk.SelectionMode.NONE;
            list.add_css_class ("navigation-sidebar");
            list.row_activated.connect ((row) => {
                var result = row.get_data<Json.Object> ("result");
                if (result != null && search.is_current (search.generation))
                    message_activated (search.account_id,
                        (int) json_int (result, "chatId"), (int) json_int (result, "id"));
            });
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            content.append (list);
            more = new Gtk.Button.with_label (_("Load more results"));
            more.visible = false;
            more.clicked.connect (() => { load_page.begin (true); });
            content.append (more);
            append (content);
            search.changed.connect (() => {
                while (list.get_first_child () != null) list.remove (list.get_first_child ());
                avatar_images.remove_all ();
                loaded = 0;
                loading = false;
                more.visible = false;
                if (search.busy) status.label = _("Searching…");
                else if (search.error_message != null) status.label = _("Search failed: ") + search.error_message;
                else if (search.query == "") status.label = _("Type to search messages");
                else if (search.ids.length == 0) status.label = _("No messages found");
                else if (search.ids.length >= 1000) status.label = _("1,000+ results · newest matches shown");
                else status.label = _("%d results").printf (search.ids.length);
                if (!search.busy && search.ids.length > 0) load_page.begin ();
            });
        }

        public void submit (string query) {
            visible = query.strip () != "";
            search.submit (query);
            if (visible && rpc != null && rpc.account_id > 0
                    && scope_account != rpc.account_id) load_scope.begin (rpc.account_id);
        }

        public void set_rpc (RpcClient rpc) {
            this.rpc = rpc;
            search.set_rpc (rpc);
            scope_account = 0;
            submit ("");
        }

        private async void load_scope (int acct_id) {
            scope_account = acct_id;
            scope.label = _("Messages in selected profile");
            try {
                string? name = yield rpc.get_config ("displayname", acct_id);
                if (rpc.account_id != acct_id || scope_account != acct_id) return;
                if (name == null || name == "")
                    name = yield rpc.get_account_address (acct_id);
                if (rpc.account_id != acct_id || scope_account != acct_id) return;
                scope.label = _("Messages in %s").printf (name ?? _("selected profile"));
            } catch (Error e) { /* The explicit selected-profile scope remains. */ }
        }

        public bool focus_first (bool activate = false) {
            var row = list.get_row_at_index (0);
            if (row == null) return false;
            if (activate) list.row_activated (row);
            else row.grab_focus ();
            return true;
        }

        private async void load_page (bool focus_new = false) {
            if (loading || loaded >= search.ids.length) return;
            loading = true;
            more.sensitive = false;
            uint token = search.generation;
            int end = int.min (loaded + 50, search.ids.length);
            int[] ids = search.ids[loaded:end];
            Json.Object? results = null;
            try {
                results = yield rpc.message_ids_to_search_results (search.account_id, ids);
            } catch (Error e) {
                /* Core fails a whole batch if one message was deleted after
                   the search. Recover the surviving rows independently. */
                results = new Json.Object ();
                foreach (int id in ids) {
                    if (!search.is_current (token)) return;
                    try {
                        var one = yield rpc.message_ids_to_search_results (search.account_id, { id });
                        if (one != null && one.has_member (id.to_string ()))
                            results.set_member (id.to_string (), one.get_member (id.to_string ()).copy ());
                    } catch (Error deleted) { /* Skip unavailable results. */ }
                }
            }
            if (!search.is_current (token)) return;
            Gtk.ListBoxRow? first = null;
            foreach (int id in ids) {
                var obj = results != null ? json_obj (results, id.to_string ()) : null;
                if (obj == null) continue;
                var row = new Gtk.ListBoxRow ();
                row.set_data<Json.Object> ("result", obj);
                string chat_name = json_str (obj, "chatName") ?? _("Chat");
                var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
                content.add_css_class ("chat-row");
                content.margin_start = content.margin_end = 8;
                content.margin_top = content.margin_bottom = 4;
                var avatar = new Adw.Avatar (40, chat_name, true);
                avatar.valign = Gtk.Align.CENTER;
                avatar.halign = Gtk.Align.CENTER;
                string? avatar_path = json_str (obj, "chatProfileImage");
                if (avatar_path != null && avatar_path != "") {
                    var texture = avatar_images.lookup (avatar_path);
                    if (texture == null) {
                        texture = load_avatar (avatar_path);
                        if (texture != null) avatar_images.insert (avatar_path, texture);
                    }
                    avatar.custom_image = texture;
                }
                content.append (avatar);
                var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
                box.hexpand = true;
                box.valign = Gtk.Align.CENTER;
                var title = new Gtk.Label (chat_name);
                title.xalign = 0;
                title.ellipsize = Pango.EllipsizeMode.END;
                title.add_css_class ("heading");
                box.append (title);
                var snippet = new Gtk.Label (MessageSearch.snippet (
                    json_str (obj, "message") ?? "", search.query));
                snippet.xalign = 0;
                snippet.wrap = true;
                snippet.wrap_mode = Pango.WrapMode.WORD_CHAR;
                snippet.lines = 2;
                snippet.ellipsize = Pango.EllipsizeMode.END;
                box.append (snippet);
                var date = new DateTime.from_unix_local (json_int (obj, "timestamp"));
                var detail = new Gtk.Label ("%s · %s%s".printf (
                    json_str (obj, "authorName") ?? "", date.format ("%x %H:%M"),
                    json_bool (obj, "isChatArchived") ? " · " + _("Archived") : ""));
                detail.xalign = 0;
                detail.ellipsize = Pango.EllipsizeMode.END;
                detail.add_css_class ("dim-label");
                box.append (detail);
                content.append (box);
                row.child = content;
                list.append (row);
                if (first == null) first = row;
            }
            loaded = end;
            loading = false;
            more.sensitive = true;
            more.visible = loaded < search.ids.length;
            if (list.get_first_child () == null) status.label = _("Results are no longer available");
            if (focus_new && first != null) first.grab_focus ();
        }
    }
}
