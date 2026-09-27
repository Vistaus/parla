using Dc;

private Gtk.Widget? search_widget (Gtk.Widget widget, Type type, string? text = null) {
    if (widget.get_type ().is_a (type)) {
        string? value = widget.name;
        if (widget is Gtk.Label) value = ((Gtk.Label) widget).label;
        else if (widget is Gtk.Button) value = ((Gtk.Button) widget).label;
        else if (widget is Gtk.SearchEntry) value = ((Gtk.SearchEntry) widget).placeholder_text;
        if (text == null || value == text || widget.tooltip_text == text) return widget;
    }
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = search_widget (child, type, text);
        if (found != null) return found;
    }
    return null;
}

private bool search_has_message (ConversationView view, int id) {
    var list = (Gtk.ListView) search_widget (view, typeof (Gtk.ListView), "conversation-messages");
    return find_message (list.model, id) != null;
}

private double search_message_top (Gtk.Widget widget, int id, Gtk.Widget scroll,
                                   bool highlighted = false) {
    var row = widget as MessageRow;
    if (row != null && row.get_mapped () && row.message_id == id
            && (!highlighted || row.has_css_class ("message-new"))) {
        Graphene.Point point;
        if (row.compute_point (scroll, Graphene.Point () { x = 0, y = 0 }, out point))
            return point.y;
    }
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        double top = search_message_top (child, id, scroll, highlighted);
        if (top != double.MAX) return top;
    }
    return double.MAX;
}

private void assert_search_message_visible (ConversationView view, int id) {
    var scroll = search_widget (view, typeof (Gtk.ScrolledWindow), "conversation-scroll");
    double top = search_message_top (view, id, scroll, true);
    assert (top >= 0 && top < scroll.get_height ());
}

private async void check_search_ui (Dc.Application app, Dc.Window window) {
    try {
        for (int i = 0; i < 100 && app.rpc.account_id == 0; i++) yield nap (50);
        yield window.open_chat_from_notification (1, 10);
        yield nap (1200);
        var view = window.current_view ();
        assert (view != null && !search_has_message (view, 50));
        var scroll = (Gtk.ScrolledWindow) search_widget (view, typeof (Gtk.ScrolledWindow), "conversation-scroll");
        double original = scroll.vadjustment.value;
        view.toggle_search ();
        var entry = (Gtk.SearchEntry) search_widget (view, typeof (Gtk.SearchEntry), "Search in conversation…");
        entry.text = "needle";
        yield nap (1300);
        assert (search_widget (view, typeof (Gtk.Label), "2 of 2") != null);
        assert (search_has_message (view, 50) && search_has_message (view, 49));
        assert (!search_has_message (view, 1000));
        var list = (Gtk.ListView) search_widget (view, typeof (Gtk.ListView), "conversation-messages");
        assert (list.model.get_n_items () <= 61);
        assert (!(yield fixture_seen (app.rpc, 20)));
        // Search keeps the entry focus so the next keystroke edits the query.
        assert (window.get_focus ().is_ancestor (entry));
        var previous = (Gtk.Button) search_widget (view, typeof (Gtk.Button), "Previous match (Shift+Enter)");
        previous.clicked ();
        yield nap (1000);
        assert (search_widget (view, typeof (Gtk.Label), "1 of 2") != null);
        assert (search_message_top (view, 20, scroll) < scroll.get_height ());
        yield app.rpc.call ("test_hold", Params.begin ().build ());
        entry.text = "far";
        yield nap (400);
        entry.text = "empty";
        yield nap (300);
        yield app.rpc.call ("test_release", Params.begin ().build ());
        yield nap (100);
        assert (!search_has_message (view, 800));
        assert (search_widget (view, typeof (Gtk.Label), "No matches") != null);
        entry.text = "deleted";
        yield nap (500);
        assert (search_widget (view, typeof (Gtk.Label), "No matches") != null);
        view.close_search_if_active ();
        yield nap (1300);
        assert (search_has_message (view, 2009));
        assert (scroll.vadjustment.upper - scroll.vadjustment.page_size - scroll.vadjustment.value < 80);
        assert (original >= 0);

        // Restore an arbitrary reading position, even after replacing its window.
        view.scroll_to_message (1000);
        yield nap (1200);
        original = search_message_top (view, 1000, scroll);
        assert (original != double.MAX);
        view.toggle_search ();
        entry.text = "needle";
        yield nap (1200);
        view.close_search_if_active ();
        yield nap (1200);
        assert (search_has_message (view, 1000));
        // Allow GTK to snap by its small row margin after rebuilding the list.
        assert (Math.fabs (search_message_top (view, 1000, scroll) - original) <= 8);
        assert (!(yield fixture_seen (app.rpc, 500)));

        var global_entry = (Gtk.SearchEntry) search_widget (window, typeof (Gtk.SearchEntry), "Search chats or messages…");
        global_entry.text = "needle";
        yield nap (500);
        var results = (SearchResultsView) search_widget (window, typeof (SearchResultsView));
        assert (search_widget (results, typeof (Gtk.Label), "Messages in Search profile") != null);
        assert (search_widget (results, typeof (Gtk.Label), "Match <20020> & context") != null);
        assert (results.focus_first (true));
        yield nap (1300);
        assert (window.current_chat_id == 20);
        assert (search_has_message (window.current_view (), 20020));
        assert_search_message_visible (window.current_view (), 20020);
        assert (!search_has_message (window.current_view (), 21999));
        assert (!(yield fixture_seen (app.rpc, 21999)));

        // Activate another result with the row focused, as a pointer click or
        // Enter does, and then jump between results within the cached chat.
        var result_rows = (Gtk.ListBox) search_widget (results, typeof (Gtk.ListBox));
        var result_row = result_rows.get_row_at_index (1);
        result_row.grab_focus ();
        result_rows.row_activated (result_row);
        yield nap (1300);
        assert (window.current_chat_id == 10);
        assert_search_message_visible (window.current_view (), 20);
        global_entry.text = "same-chat";
        yield nap (400);
        assert (results.focus_first (true));
        yield nap (1300);
        assert_search_message_visible (window.current_view (), 1000);
        result_row = result_rows.get_row_at_index (1);
        result_row.grab_focus ();
        result_rows.row_activated (result_row);
        yield nap (1300);
        assert_search_message_visible (window.current_view (), 1020);

        global_entry.text = "many";
        yield nap (500);
        assert (search_widget (results, typeof (Gtk.Label), "1,000+ results · newest matches shown") != null);
        var rows = (Gtk.ListBox) search_widget (results, typeof (Gtk.ListBox));
        assert (rows.get_row_at_index (49) != null && rows.get_row_at_index (50) == null);
        var more = (Gtk.Button) search_widget (results, typeof (Gtk.Button), "Load more results");
        for (int page = 1; page < 20; page++) {
            more.clicked ();
            yield nap (100);
            assert (rows.get_row_at_index (page * 50).has_focus);
        }
        assert (rows.get_row_at_index (999) != null && !more.visible);
        global_entry.text = "deleted";
        yield nap (500);
        assert (rows.get_row_at_index (0) != null && rows.get_row_at_index (1) == null);
        assert (results.focus_first (true));
        yield nap (1200);
        assert (window.current_chat_id == 10 && search_has_message (window.current_view (), 20));
        assert_search_message_visible (window.current_view (), 20);
        global_entry.text = "needle";
        yield window.switch_account (2);
        yield nap (400);
        assert (!results.visible && global_entry.text == "");
        assert (results.search.ids.length == 0);
        var batches = (yield app.rpc.call ("test_batches", Params.begin ().build ())).get_array ();
        for (uint i = 0; i < batches.get_length (); i++) assert (batches.get_array_element (i).get_length () <= 100);
        app.rpc.stop ();
        window.destroy ();
        stdout.printf ("Search UI: distant context, restore, archived chats, paging, deletion and profile switch: PASS\n");
    } catch (Error e) { error ("Search UI: %s", e.message); }
}

public int run_search_ui_test () {
    Adw.init ();
    var app = new Dc.Application ();
    app.flags |= ApplicationFlags.NON_UNIQUE;
    try { app.register (null); }
    catch (Error e) { error ("Register test app: %s", e.message); }
    var window = new Dc.Window (app);
    window.present ();
    var loop = new MainLoop ();
    check_search_ui.begin (app, window, () => { loop.quit (); });
    loop.run ();
    return 0;
}
