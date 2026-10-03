using Dc;

private int retired_chat_rows;
private int finalized_chat_rows;
private int opened_conversations;
private int finalized_conversations;
private int created_message_rows;
private int finalized_message_rows;
private int opened_media_bars;
private int finalized_media_bars;
private int opened_composers;
private int finalized_composers;

private void watch_chat_rows (Gtk.Widget widget) {
    if (widget is ChatRow) {
        assert (((ChatRow) widget).accept_file_drop ());
        retired_chat_rows++;
        widget.weak_ref (() => { finalized_chat_rows++; });
        return;
    }
    for (var child = widget.get_first_child (); child != null;
            child = child.get_next_sibling ()) watch_chat_rows (child);
}

private void report_chat_memory (int refreshes) {
    stdout.printf ("refreshes=%d retired=%d finalized=%d retained=%d",
        refreshes, retired_chat_rows, finalized_chat_rows,
        retired_chat_rows - finalized_chat_rows);
    // Optional Linux RSS samples complement the portable lifetime assertion.
    try {
        string status;
        FileUtils.get_contents ("/proc/self/status", out status);
        foreach (string line in status.split ("\n")) {
            if (line.has_prefix ("VmRSS:")) stdout.printf (" %s", line.strip ());
        }
    } catch (Error e) {}
    stdout.printf ("\n");
    stdout.flush ();
}

private async void check_chat_lifetime (Dc.Application app, Dc.Window window,
                                        int refreshes) {
    for (int i = 0; i < 200 && window.chat_store.get_n_items () != 12; i++)
        yield nap (25);
    assert (window.chat_store.get_n_items () == 12);
    yield nap (100);
    report_chat_memory (0);
    for (int i = 0; i < refreshes; i++) {
        watch_chat_rows (window);
        // Every response changes the preview of all twelve chats, as
        // incoming messages or history synchronization would do.
        yield window.load_chats ();
        yield nap (10);
        if ((i + 1) % 10 == 0) report_chat_memory (i + 1);
    }
    yield nap (100);
    report_chat_memory (refreshes);
    assert (retired_chat_rows == 12 * refreshes);
    app.rpc.stop ();
    window.destroy ();
}

private void watch_message_rows (Gtk.Widget widget) {
    if (widget is ConversationMediaBar) {
        opened_media_bars++;
        widget.weak_ref (() => { finalized_media_bars++; });
    }
    if (widget is ComposeBar) {
        opened_composers++;
        widget.weak_ref (() => { finalized_composers++; });
    }
    if (widget is MessageRow) {
        if (!widget.get_data<bool> ("lifetime-watched")) {
            widget.set_data<bool> ("lifetime-watched", true);
            created_message_rows++;
            widget.weak_ref (() => { finalized_message_rows++; });
        }
        return;
    }
    for (var child = widget.get_first_child (); child != null;
            child = child.get_next_sibling ()) watch_message_rows (child);
}

private void watch_conversation (ConversationView view) {
    opened_conversations++;
    view.weak_ref (() => { finalized_conversations++; });
    watch_message_rows (view);
}

private async void check_switch_lifetime (Dc.Application app, Dc.Window window,
                                          int switches) {
    for (int i = 0; i < 200 && window.chat_store.get_n_items () != 12; i++)
        yield nap (25);
    assert (window.chat_store.get_n_items () == 12);
    for (int i = 0; i < switches; i++) {
        yield window.open_chat_from_notification (1, 10 + i % 12);
        yield nap (400);
        watch_conversation (window.current_view ());
        // The active conversation and two recent neighbours are cached.
        // Evicted controls must follow their view, including hidden popovers.
        assert (opened_conversations - finalized_conversations <= 3);
        assert (opened_media_bars - finalized_media_bars <= 3);
        assert (opened_composers - finalized_composers <= 3);
        if ((i + 1) % 12 == 0) {
            stdout.printf ("switches=%d live_views=%d live_messages=%d\n", i + 1,
                opened_conversations - finalized_conversations,
                created_message_rows - finalized_message_rows);
            report_chat_memory (0);
        }
    }
    window.quit_application ();
    app.rpc.stop ();
    yield nap (1000);
    stdout.printf ("After closing: views=%d/%d messages=%d/%d media=%d/%d composers=%d/%d finalized\n",
        finalized_conversations, opened_conversations,
        finalized_message_rows, created_message_rows,
        finalized_media_bars, opened_media_bars,
        finalized_composers, opened_composers);
}

public int run_chat_lifetime_test (int refreshes, bool switching = false) {
    assert (refreshes > 0);
    Adw.init ();
    Gtk.Settings.get_default ().gtk_enable_animations = false;
    var app = new Dc.Application ();
    app.flags |= ApplicationFlags.NON_UNIQUE;
    try { app.register (null); }
    catch (Error e) { error ("Register test app: %s", e.message); }
    var window = new Dc.Window (app);
    window.present ();
    var loop = new MainLoop ();
    if (switching)
        check_switch_lifetime.begin (app, window, refreshes, () => { loop.quit (); });
    else
        check_chat_lifetime.begin (app, window, refreshes, () => { loop.quit (); });
    loop.run ();
    if (switching) {
        assert (created_message_rows > 0);
        // The window is still owned here; pending GTK callbacks can retain
        // its last view briefly. Check eviction above and row teardown here.
        return finalized_media_bars == finalized_conversations
            && finalized_composers == finalized_conversations
            && finalized_message_rows == created_message_rows ? 0 : 1;
    }
    return finalized_chat_rows == retired_chat_rows ? 0 : 1;
}
