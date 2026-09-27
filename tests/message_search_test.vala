using Dc;

private async void check_message_search () {
    var rpc = new RpcClient ();
    try {
        yield rpc.start ({ test_executable, "--fake-retry" });
        rpc.account_id = 1;
        var search = new MessageSearch (rpc);
        search.submit ("one", 10);
        search.submit ("two", 10);
        search.submit (" three ", 10);
        yield nap (300);
        assert (!search.busy && search.ids.length == 2);
        var calls = (yield rpc.call ("test_calls", Params.begin ().build ())).get_array ();
        assert (calls.get_length () == 1);
        var args = calls.get_object_element (0).get_array_member ("params");
        assert (args.get_int_element (0) == 1);
        assert (args.get_string_element (1) == "three");
        assert (args.get_int_element (2) == 10);

        yield rpc.call ("test_hold", Params.begin ().add_string ("search_messages").build ());
        search.submit ("old", 10);
        yield nap (300);
        search.submit ("empty", 20);
        // Release during the debounce: invalidation must already have happened.
        yield rpc.call ("test_release", Params.begin ().build ());
        assert (search.busy && search.ids.length == 0);
        yield nap (300);
        assert (!search.busy && search.ids.length == 0);

        yield rpc.call ("test_hold", Params.begin ().add_string ("search_messages").build ());
        search.submit ("profile one");
        yield nap (300);
        rpc.account_id = 2;
        yield rpc.call ("test_release", Params.begin ().build ());
        assert (search.ids.length == 0);
        search.submit ("profile two");
        yield nap (300);
        assert (search.ids[0] == 200);
        calls = (yield rpc.call ("test_calls", Params.begin ().build ())).get_array ();
        args = calls.get_object_element (calls.get_length () - 1).get_array_member ("params");
        assert (args.get_int_element (0) == 2 && args.get_element (2).is_null ());

        yield rpc.call ("test_fail", Params.begin ().add_string ("search_messages").build ());
        search.submit ("failure");
        yield nap (300);
        assert (!search.busy && search.error_message != null && search.ids.length == 0);
        search.submit ("cancel");
        search.cancel ();
        yield nap (300);
        assert (!search.busy && search.ids.length == 0);
        var results = yield rpc.message_ids_to_search_results (1, { 100 });
        assert (results.get_object_member ("100").get_string_member ("message") == "<literal>");
    } catch (Error e) { error ("Search: %s", e.message); }
    rpc.stop ();
}

public void test_message_search () {
    assert (MessageSearch.snippet ("café\n<literal>", "CAFÉ") == "café <literal>");
    var long_text = string.nfill (1000, 'a') + "café" + string.nfill (1000, 'b');
    var snippet = MessageSearch.snippet (long_text, "CAFÉ");
    assert (snippet.contains ("café") && snippet.char_count () <= 242);
    var loop = new MainLoop ();
    check_message_search.begin (() => { loop.quit (); });
    loop.run ();
}
