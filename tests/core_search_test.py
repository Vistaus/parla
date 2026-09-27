#!/usr/bin/env python3
"""Check native search contracts in disposable offline accounts (no network I/O)."""
from pathlib import Path
import sys
import tempfile

from core_unread_test import Core
from core_retry_test import expect_no_transport


def check_search(binary):
    with tempfile.TemporaryDirectory(prefix="parla-native-search-") as folder:
        core = Core(binary, folder)
        try:
            account = core.call("add_account")
            chats = []
            for name in ("First", "Archived"):
                contact = core.call("create_contact", account, f"{name.lower()}@example.org", name)
                chats.append(core.call("create_chat_by_contact_id", account, contact))
            for i in range(70):
                expect_no_transport(core, "send_msg", account, chats[0], dict(text=f"Context {i}"))
            expect_no_transport(core, "send_msg", account, chats[0], dict(text="Needle café <literal>"))
            expect_no_transport(core, "send_msg", account, chats[1], dict(text="Needle café archived"))
            core.call("set_chat_visibility", account, chats[1], "Archived")
            ids = core.call("search_messages", account, "needle café", None)
            assert len(ids) == 2
            before = {i: core.call("get_message", account, i)["state"] for i in ids}
            results = core.call("message_ids_to_search_results", account, ids)
            assert {r["chatId"] for r in results.values()} == set(chats)
            assert any(r["isChatArchived"] for r in results.values())
            assert all(r["timestamp"] > 0 and r["chatName"] and r["message"] for r in results.values())
            scoped = core.call("search_messages", account, "needle café", chats[0])
            assert len(scoped) == 1 and scoped[0] in ids
            assert core.call("search_messages", account, "no match here", None) == []
            assert {i: core.call("get_message", account, i)["state"] for i in ids} == before
            another = core.call("add_account")
            assert core.call("search_messages", another, "needle café", None) == []
        finally:
            core.close()
    print("Native scoped/global search, archived metadata, Unicode, profile isolation and unchanged read state: PASS")


if __name__ == "__main__":
    check_search(str(Path(sys.argv[1]).resolve()))
