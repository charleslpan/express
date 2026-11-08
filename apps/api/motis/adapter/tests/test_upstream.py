"""Tests for upstream.py. Run from apps/api/motis/adapter:

    python3 -m unittest discover -s tests
"""

import os
import sys
import threading
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from upstream import MAX_EARLY_AGE, Upstream  # noqa: E402


class SlowFeeds:
    """Answers each URL with its name after `delay` seconds, counting fetches."""

    def __init__(self, delay=0.0, fail=()):
        self.delay = delay
        self.fail = set(fail)
        self.calls: list[str] = []
        self._lock = threading.Lock()

    def __call__(self, url):
        with self._lock:
            self.calls.append(url)
            n = self.calls.count(url)
        time.sleep(self.delay)
        if url in self.fail and n == 1:
            raise OSError("upstream down")
        return f"{url}#{n}".encode()


class UpstreamTest(unittest.TestCase):
    def test_start_fetches_every_feed_in_parallel(self):
        feeds = SlowFeeds(delay=0.2)
        up = Upstream(feeds)
        urls = [f"feed{i}" for i in range(11)]
        t = time.monotonic()
        up.start(urls)
        self.assertEqual([up.get(u) for u in urls], [f"{u}#1".encode() for u in urls])
        # One round trip for all eleven, not eleven in a row.
        self.assertLess(time.monotonic() - t, 1.0)
        self.assertEqual(sorted(feeds.calls), sorted(urls))

    def test_only_the_first_get_takes_the_early_result(self):
        feeds = SlowFeeds()
        up = Upstream(feeds)
        up.start(["a"])
        self.assertEqual(up.get("a"), b"a#1")
        self.assertEqual(up.get("a"), b"a#2")

    def test_a_url_not_started_fetches_live(self):
        feeds = SlowFeeds()
        up = Upstream(feeds)
        up.start(["a"])
        self.assertEqual(up.get("b"), b"b#1")

    def test_a_failed_early_fetch_fetches_again(self):
        feeds = SlowFeeds(fail={"a"})
        up = Upstream(feeds)
        up.start(["a"])
        with self.assertLogs("adapter", "WARNING"):
            self.assertEqual(up.get("a"), b"a#2")

    def test_a_stale_early_result_is_dropped(self):
        now = [100.0]
        feeds = SlowFeeds()
        up = Upstream(feeds, clock=lambda: now[0])
        up.start(["a"])
        now[0] += MAX_EARLY_AGE + 1
        self.assertEqual(up.get("a"), b"a#2")


if __name__ == "__main__":
    unittest.main()
