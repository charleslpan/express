"""Upstream fetches for the adapter, with every feed fetched once in parallel
the moment the adapter starts.

After a cold start MOTIS answers 503 until its first realtime cycle is in
(`when_unhealthy_return_error` in config.yml), and that cycle waits on every
feed. `start()` fetches them all at once while MOTIS is still loading, and the
first `get()` of each URL takes that early result, so the first cycle costs one
round trip instead of one per feed. Later gets fetch live.
"""

from __future__ import annotations

import logging
import threading
import time
from collections.abc import Callable, Iterable
from concurrent.futures import Future, ThreadPoolExecutor

# An early result older than this is dropped and fetched live: MOTIS polls
# every 30 s, and the feeds themselves move about that often.
MAX_EARLY_AGE = 30  # s

log = logging.getLogger("adapter")


class Upstream:
    def __init__(self, fetch: Callable[[str], bytes], clock: Callable[[], float] = time.monotonic):
        self._fetch = fetch
        self._clock = clock
        self._lock = threading.Lock()
        self._early: dict[str, tuple[float, Future[bytes]]] = {}

    def start(self, urls: Iterable[str]) -> None:
        """Fetches every URL in parallel, in the background, for its first get()."""
        urls = list(dict.fromkeys(urls))
        if not urls:
            return
        pool = ThreadPoolExecutor(max_workers=len(urls), thread_name_prefix="prefetch")
        now = self._clock()
        with self._lock:
            for url in urls:
                self._early[url] = (now, pool.submit(self._fetch, url))
        pool.shutdown(wait=False)

    def get(self, url: str) -> bytes:
        """The early result for `url` if it is the first get and still fresh, else a live fetch."""
        with self._lock:
            early = self._early.pop(url, None)
        if early is not None:
            at, future = early
            if self._clock() - at < MAX_EARLY_AGE:
                try:
                    return future.result()
                except Exception as e:  # fall back to a live fetch
                    log.warning("early fetch failed, fetching again: %s", type(e).__name__)
        return self._fetch(url)
