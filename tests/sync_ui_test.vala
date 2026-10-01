using Dc;

private async void sync_ui_pause (uint milliseconds) {
    Timeout.add (milliseconds, sync_ui_pause.callback);
    yield;
}

private Gtk.ListBoxRow? sync_chat_row (Gtk.Widget widget, int id) {
    var row = widget as Gtk.ListBoxRow;
    var chat = row != null ? row.child as ChatRow : null;
    if (chat != null && chat.chat_id == id) return row;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = sync_chat_row (child, id);
        if (found != null) return found;
    }
    return null;
}

private bool sync_status_visible (Gtk.Widget widget) {
    var title = widget as Adw.WindowTitle;
    if (title != null && title.subtitle == "Syncing…") return true;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        if (sync_status_visible (child)) return true;
    }
    return false;
}

private async void check_sync_ui (Dc.Application app, Dc.Window window) {
    try {
        for (int i = 0; i < 100 && (window.chat_store.get_n_items () != 3
                || !sync_status_visible (window)); i++) yield sync_ui_pause (50);
        assert (window.chat_store.get_n_items () == 3);
        assert (sync_status_visible (window));
        var row10 = sync_chat_row (window, 10);
        var row20 = sync_chat_row (window, 20);
        var row30 = sync_chat_row (window, 30);
        var unchanged = row20.child;
        var list = (Gtk.ListBox) row10.get_parent ();
        list.row_activated (row10);
        yield sync_ui_pause (300);
        yield app.rpc.call ("test_burst", Params.begin ().build ());
        // More than 500 core events across several refresh intervals.
        for (int i = 0; i < 15; i++) {
            yield sync_ui_pause (200);
            assert (sync_chat_row (window, 10) == row10);
            assert (sync_chat_row (window, 20) == row20);
            assert (row20.child == unchanged);
            list.row_activated (i % 2 == 0 ? row20 : row10);
            assert (window.current_chat_id == (i % 2 == 0 ? 20 : 10));
        }
        var counts = (yield app.rpc.call ("test_calls", Params.begin ().build ())).get_object ();
        int64 chat_loads = json_int (counts, "get_chatlist_items_by_entries");
        int64 unread_loads = json_int (counts, "get_all_accounts");
        assert (chat_loads > 0 && chat_loads <= 3);
        assert (unread_loads > 0 && unread_loads <= 4);
        stdout.printf ("Sync burst: %lld chat refreshes, %lld unread refreshes\n", chat_loads, unread_loads);

        var final_revision = yield app.rpc.call ("test_finish", Params.begin ().build ());
        yield sync_ui_pause (600);
        assert (!sync_status_visible (window));
        assert (find_chat_entry (window.chat_store, 10).last_message
            == "History %lld".printf (final_revision.get_int ()));
        assert (list.get_row_at_index (0) == row30);
        assert (sync_chat_row (window, 20) == row20);

        // A slow background load must not restore its earlier selection.
        list.row_activated (row10);
        yield sync_ui_pause (300);
        yield app.rpc.call ("test_hold", Params.begin ().build ());
        window.load_chats.begin ();
        for (int i = 0; i < 100; i++) {
            if ((yield app.rpc.call ("test_held", Params.begin ().build ())).get_boolean ()) break;
            yield sync_ui_pause (20);
        }
        list.row_activated (row20);
        yield app.rpc.call ("test_release", Params.begin ().build ());
        yield sync_ui_pause (300);
        assert (window.current_chat_id == 20);
        assert ((row20.get_state_flags () & Gtk.StateFlags.SELECTED) != 0);
        assert ((row10.get_state_flags () & Gtk.StateFlags.SELECTED) == 0);

        // Removing one chat must not disturb a surviving selected row.
        yield app.rpc.call ("test_remove", Params.begin ().build ());
        yield sync_ui_pause (400);
        assert (sync_chat_row (window, 30) == null);
        assert (sync_chat_row (window, 20) == row20);
        assert (window.current_chat_id == 20);
        app.rpc.stop ();
        window.destroy ();
        stdout.printf ("Sync status, batching, row identity, activation and final flush: PASS\n");
    } catch (Error e) {
        error ("Sync UI: %s", e.message);
    }
}

public int run_sync_ui_test () {
    Adw.init ();
    var app = new Dc.Application ();
    app.flags |= ApplicationFlags.NON_UNIQUE;
    try { app.register (null); }
    catch (Error e) { error ("Register test app: %s", e.message); }
    var window = new Dc.Window (app);
    window.present ();
    var loop = new MainLoop ();
    check_sync_ui.begin (app, window, () => loop.quit ());
    loop.run ();
    return 0;
}
