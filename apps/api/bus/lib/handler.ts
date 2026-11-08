import {
  compactFleet,
  decodeFleet,
  expandFleet,
  filterFleet,
  parseQuery,
  type CompactFleet,
  type Fleet,
} from "./fleet.js";

/** MTA Bus Time's GTFS-RT vehicle positions for the whole fleet. */
export const FEED_URL = "https://gtfsrt.prod.obanyc.com/vehiclePositions";
export const CACHE_KEY = "mta-bus-time:vehicle-positions:v2";
export const TTL_SECONDS = 30;
/** How long the CDN may keep serving a stale answer while it refetches one in the background. */
export const STALE_SECONDS = 30;
const UPSTREAM_TIMEOUT_MS = 10_000;

/** The part of Vercel's RuntimeCache this handler uses. */
export interface FleetCache {
  get(key: string): Promise<unknown | null>;
  set(key: string, value: unknown, options?: { ttl?: number; name?: string }): Promise<void>;
}

/** The fleet and when it was fetched (Unix ms), so every instance knows how fresh a cached copy is. */
interface Entry {
  fetchedAt: number;
  fleet: Fleet;
}

/** An `Entry` as the Runtime Cache stores it. */
interface StoredEntry {
  fetchedAt: number;
  fleet: CompactFleet;
}

function readEntry(value: unknown): Entry | null {
  const stored = value as StoredEntry | null;
  if (typeof stored?.fetchedAt !== "number" || !Array.isArray(stored.fleet?.vehicles)) return null;
  return { fetchedAt: stored.fetchedAt, fleet: expandFleet(stored.fleet) };
}

export interface Deps {
  cache: () => FleetCache;
  /** Bus Time API key; read per request so a newly added env var is picked up. */
  apiKey: () => string | undefined;
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

  async function loadFleet(key: string): Promise<Fleet> {
    if (fresh(local)) return local.fleet;
    inFlight ??= (async () => {
      const cache = deps.cache();
      const cached = readEntry(await cache.get(CACHE_KEY).catch(() => null));
      if (fresh(cached)) return cached;

      const url = `${FEED_URL}?key=${encodeURIComponent(key)}`;
      const res = await deps.fetch(url, { signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS) });
      if (!res.ok) throw new UpstreamError(`Bus Time answered ${res.status}`);
      const entry: Entry = { fetchedAt: Date.now(), fleet: decodeFleet(new Uint8Array(await res.arrayBuffer())) };
      const stored: StoredEntry = { fetchedAt: entry.fetchedAt, fleet: compactFleet(entry.fleet) };
      // A failed cache write still answers this request from the fresh fetch.
      await cache.set(CACHE_KEY, stored, { ttl: TTL_SECONDS, name: "bus fleet" }).catch(() => undefined);
      return entry;
    })().finally(() => {
      inFlight = null;
    });
    local = await inFlight;
    return local.fleet;
  }

  return async function handle(request: Request): Promise<Response> {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response(null, { status: 405, headers: { allow: "GET, HEAD" } });
    }
    const query = parseQuery(new URL(request.url).searchParams);
    if ("error" in query) return noStore(400, query.error);

    const key = deps.apiKey();
    if (!key) return noStore(503, "bus positions are not configured");

    let fleet: Fleet;
    try {
      fleet = await loadFleet(key);
    } catch (err) {
      // Never echo the upstream URL: it carries the key.
      const reason = err instanceof UpstreamError ? err.message : "Bus Time is unreachable";
      console.error("bus fleet fetch failed:", reason);
      return noStore(502, "bus positions are unavailable");
    }
    return json(200, filterFleet(fleet, query), `public, max-age=0, s-maxage=${TTL_SECONDS}, stale-while-revalidate=${STALE_SECONDS}`);
  };
}

class UpstreamError extends Error {}
