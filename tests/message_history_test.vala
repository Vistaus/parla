using Dc;

private Json.Array message_ids () {
    var ids = new Json.Array ();
    ids.add_int_element (10);
    ids.add_int_element (20);
    ids.add_int_element (30);
    return ids;
}

private void test_find_id () {
    var ids = message_ids ();
    assert (MessageHistory.find_id (ids, 10) == 0);
    assert (MessageHistory.find_id (ids, 20) == 1);
    assert (MessageHistory.find_id (ids, 30) == 2);
    assert (MessageHistory.find_id (ids, 99) == -1);
}

private void test_distant_context () {
    var ids = new Json.Array ();
    for (int i = 0; i < 10000; i++) ids.add_int_element (i + 10);
    foreach (uint target in new uint[] { 0, 1, 30, 5000, 9999 }) {
        uint start, end;
        MessageHistory.context_range (ids, target, out start, out end);
        assert (start <= target && target < end);
        assert (end <= ids.get_length () && end - start <= 61);
        assert (target - start == uint.min (target, 30));
        assert (end - target == uint.min (10000 - target, 31));
    }
}

private void test_initial_unread_batch () {
    var ids = new Json.Array ();
    // Core order, which can differ from numeric ID order, is authoritative.
    for (int i = 100; i > 0; i--) ids.add_int_element (i);
    assert (MessageHistory.initial_batch_start (ids, 0) == 70);
    assert (MessageHistory.initial_batch_start (ids, 999) == 70);
    assert (MessageHistory.initial_batch_start (ids, 95) == 4);
    assert (MessageHistory.initial_batch_start (ids, 100) == 0);
    assert (MessageHistory.initial_batch_start (ids, 1) == 70);
    assert (MessageHistory.initial_batch_start (message_ids (), 20) == 0);
    assert (MessageHistory.initial_batch_start (new Json.Array (), 0) == 0);
}

public int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/message-history/find-id", test_find_id);
    Test.add_func ("/message-history/initial-unread-batch", test_initial_unread_batch);
    Test.add_func ("/message-history/distant-context", test_distant_context);
    return Test.run ();
}
