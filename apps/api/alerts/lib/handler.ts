import { indexAlerts, parseLines, selectLines, type AlertIndex } from "./alerts.js";

/** The MTA's GTFS-RT alert feeds as JSON, which carry the MTA's alert type (no key needed). */
export const FEED_URLS = {
  subway: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/camsys%2Fsubway-alerts.json",
  bus: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/camsys%2Fbus-alerts.json",
} as const;
export const CACHE_KEY = "mta-alerts:index:v2";
export const TTL_SECONDS = 60;
/** How long the CDN may keep serving a stale answer while it refetches one in the background. */
export const STALE_SECONDS = 60;
const UPSTREAM_TIMEOUT_MS = 10_000;

/** The part of Vercel's RuntimeCache this handler uses. */
export interface AlertCache {
  get(key: string): Promise<unknown | null>;
  set(key: string, value: unknown, options?: { ttl?: number; name?: string }): Promise<void>;
}

/** The index and when it was fetched (Unix ms), so every instance knows how fresh a cached copy is. */
interface Entry {
  fetchedAt: number;
  index: AlertIndex;
}

function readEntry(value: unknown): Entry | null {
  const entry = value as Entry | null;
  return typeof entry?.fetchedAt === "number" && typeof entry.index?.lines === "object" ? entry : null;
}

export interface Deps {
  cache: () => AlertCache;
  fetch: typeof fetch;
}

const json = (status: number, body: unknown, cacheControl: string) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": cacheControl },
  });

const noStore = (status: number, error: string) => json(status, { error }, "no-store");

export function createHandler(deps: Deps) {
  // This instance's copy, used until it is TTL_SECONDS old: Fluid reuses warm
  // instances, so most requests never touch the Runtime Cache, which is billed
  // per 8 KB read and pauses once Hobby's monthly allowance is spent.
  let local: Entry | null = null;
  // Requests that find the local copy stale share one cache read (and fetch).
  let inFlight: Promise<Entry> | null = null;
  const fresh = (entry: Entry | null): entry is Entry =>
    entry !== null && Date.now() - entry.fetchedAt < TTL_SECONDS * 1000;
  // Log each unknown MTA alert type once per instance, not on every refresh.
  const warned = new Set<string>();

  async function fetchFeed(url: string): Promise<unknown> {
    const res = await deps.fetch(url, { signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS) });
    if (!res.ok) throw new Error(`MTA alerts answered ${res.status}`);
    return res.json();
  }

  async function loadIndex(): Promise<AlertIndex> {
    if (fresh(local)) return local.index;
    inFlight ??= (async () => {
      const cache = deps.cache();
      const cached = readEntry(await cache.get(CACHE_KEY).catch(() => null));
      if (fresh(cached)) return cached;

      const [subway, bus] = await Promise.all([fetchFeed(FEED_URLS.subway), fetchFeed(FEED_URLS.bus)]);
      const index = indexAlerts(subway, bus, (type) => {
        const key = type ?? "(none)";
        if (warned.has(key)) return;
        warned.add(key);
        console.warn(`unknown MTA alert type, mapped to the fallback: ${key}`);
      });
      const entry: Entry = { fetchedAt: Date.now(), index };
      // A failed cache write still answers this request from the fresh fetch.
      await cache.set(CACHE_KEY, entry, { ttl: TTL_SECONDS, name: "mta alerts" }).catch(() => undefined);
      return entry;
    })().finally(() => {
      inFlight = null;
    });
    local = await inFlight;
    return local.index;
  }

  return async function handle(request: Request): Promise<Response> {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response(null, { status: 405, headers: { allow: "GET, HEAD" } });
    }
    const lines = parseLines(new URL(request.url).search);
    if ("error" in lines) return noStore(400, lines.error);

    let index: AlertIndex;
    try {
      index = await loadIndex();
    } catch (err) {
      console.error("MTA alerts fetch failed:", err instanceof Error ? err.message : err);
      return noStore(502, "alerts are unavailable");
    }
    return json(200, selectLines(index, lines), `public, max-age=0, s-maxage=${TTL_SECONDS}, stale-while-revalidate=${STALE_SECONDS}`);
  };
}
