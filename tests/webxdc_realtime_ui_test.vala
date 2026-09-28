using Dc;

public int run_realtime_settings_test () {
    assert (Environment.get_variable ("PARLA_TEST_CONFIG") == Environment.get_user_config_dir ());
    var settings = new SettingsManager ();
    settings.load ();
    assert (settings.webxdc_realtime);
    assert (!settings.webxdc_allow_internet);
    settings.save_webxdc_realtime (false);
    var restored = new SettingsManager ();
    restored.load ();
    assert (!restored.webxdc_realtime && !restored.webxdc_allow_internet);
    restored.save_webxdc_realtime (true);
    settings.load ();
    assert (settings.webxdc_realtime && !settings.webxdc_allow_internet);
    stdout.printf ("Realtime enabled by default, persisted opt-out, separate internet policy: PASS\n");
    return 0;
}

#if WEBXDC && !MACOS && !WINDOWS
private WebKit.WebView? realtime_view_in (Gtk.Widget widget) {
    if (widget is WebKit.WebView) return widget as WebKit.WebView;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = realtime_view_in (child);
        if (found != null) return found;
    }
    return null;
}

private WebKit.WebView? realtime_view (WebKit.WebView? except = null) {
    var windows = Gtk.Window.get_toplevels ();
    for (uint i = 0; i < windows.get_n_items (); i++) {
        var view = realtime_view_in ((Gtk.Window) windows.get_item (i));
        if (view != null && view != except) return view;
    }
    return null;
}

private async void wait_realtime_js (WebKit.WebView view, string condition) throws Error {
    for (int i = 0; i < 200; i++) {
        var value = yield view.evaluate_javascript (condition, -1, null, null, null);
        if (value.to_boolean ()) return;
        yield nap (20);
    }
    error ("Webxdc JS condition not met: %s", condition);
}

private async void check_realtime_ui () {
    var rpc = new RpcClient ();
    var settings = new SettingsManager ();
    settings.load ();
    try {
        yield rpc.start ({ test_executable, "--fake-realtime" });
        rpc.account_id = 1;
        Webxdc.setup (rpc, settings);
        var handler = new EventHandler (rpc);
        handler.start.begin ();
        yield rpc.call ("test_link", Params.begin ().build ());
        var msg = new Message ();
        msg.id = 100;
        msg.chat_id = 10;
        msg.file_name = "realtime.xdc";
        Webxdc.open (null, rpc, msg);
        var alice = realtime_view ();
        assert (alice != null);
        rpc.account_id = 2;
        Webxdc.open (null, rpc, msg);
        var bob = realtime_view (alice);
        assert (bob != null);
        assert (Webxdc.running_apps (1, 10).length == 1);
        assert (Webxdc.running_apps (2, 10).length == 1);
        foreach (var view in new WebKit.WebView[] { alice, bob }) {
            assert (!view.get_settings ().enable_webrtc);
            assert (!view.get_settings ().enable_webgl);
            yield wait_realtime_js (view, "!!window.webxdc && !!webxdc.joinRealtimeChannel");
            yield view.evaluate_javascript ("window.channel = webxdc.joinRealtimeChannel(); channel.setListener(data => window.received = Array.from(data)); true;", -1, null, null, null);
        }
        yield realtime_calls (rpc, 2);
        yield alice.evaluate_javascript ("channel.send(new Uint8Array([0,127,128,255])); true;", -1, null, null, null);
        yield wait_realtime_js (bob, "JSON.stringify(window.received) === '[0,127,128,255]'");
        yield bob.evaluate_javascript ("channel.send(new Uint8Array([255,0,128])); true;", -1, null, null, null);
        yield wait_realtime_js (alice, "JSON.stringify(window.received) === '[255,0,128]'");

        // Deleting a background profile's app must not close the other one.
        Webxdc.handle_event (rpc, 1, "WebxdcInstanceDeleted", object_from_json ("{\"msgId\":100}"));
        assert (Webxdc.running_apps (1, 10).length == 0);
        assert (Webxdc.is_running (100));
        yield realtime_calls (rpc, 5);

        settings.save_webxdc_realtime (false);
        yield realtime_calls (rpc, 6);
        for (int i = 0; i < 100 && Webxdc.is_running (100); i++) yield nap (10);
        assert (!Webxdc.is_running (100));
        settings.load ();
        assert (!settings.webxdc_realtime);
        Webxdc.open (null, rpc, msg);
        var disabled = realtime_view ();
        assert (disabled != null);
        yield wait_realtime_js (disabled, "!!window.webxdc");
        var value = yield disabled.evaluate_javascript ("typeof webxdc.joinRealtimeChannel", -1, null, null, null);
        assert (value.to_string () == "undefined");
        yield disabled.evaluate_javascript ("window.webkit.messageHandlers.webxdc.postMessage(JSON.stringify({type:'realtime-join',channel:'bypass'})); true;", -1, null, null, null);
        assert ((yield realtime_calls (rpc, 6)).get_length () == 6);
        settings.save_webxdc_realtime (true);
        for (int i = 0; i < 100 && Webxdc.is_running (100); i++) yield nap (10);
        Webxdc.open (null, rpc, msg);
        var reopened = realtime_view ();
        assert (reopened != null);
        yield wait_realtime_js (reopened, "!!window.webxdc && !!webxdc.joinRealtimeChannel");
        yield reopened.evaluate_javascript ("webxdc.joinRealtimeChannel(); true;", -1, null, null, null);
        yield realtime_calls (rpc, 7);
        settings.save_webxdc_apps (false);
        for (int i = 0; i < 100 && Webxdc.is_running (100); i++) yield nap (10);
        assert (!Webxdc.is_running (100));
        Webxdc.open (null, rpc, msg);
        assert (!Webxdc.is_running (100));
        yield realtime_calls (rpc, 8);
        stdout.printf ("Two WebKit apps exchange binary data; profile isolation, deletion and settings closure: PASS\n");
    } catch (Error e) { error ("Realtime UI: %s", e.message); }
    rpc.stop ();
}

public int run_realtime_ui_test () {
    Adw.init ();
    var loop = new MainLoop ();
    check_realtime_ui.begin (() => { loop.quit (); });
    loop.run ();
    return 0;
}
#endif
