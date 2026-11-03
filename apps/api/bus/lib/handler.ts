import { decodeFleet, filterFleet, parseQuery, type Fleet } from "./fleet.js";

/** MTA Bus Time's GTFS-RT vehicle positions for the whole fleet. */
export const FEED_URL = "https://gtfsrt.prod.obanyc.com/vehiclePositions";
export const CACHE_KEY = "mta-bus-time:vehicle-positions:v1";
export const TTL_SECONDS = 30;
const UPSTREAM_TIMEOUT_MS = 10_000;

/** The part of Vercel's RuntimeCache this handler uses. */
export interface FleetCache {
  get(key: string): Promise<unknown | null>;
  set(key: string, value: unknown, options?: { ttl?: number; name?: string }): Promise<void>;
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
  // Requests that miss the Runtime Cache on the same instance share one fetch.
  let inFlight: Promise<Fleet> | null = null;

  async function loadFleet(key: string): Promise<Fleet> {
    const cache = deps.cache();
    const cached = (await cache.get(CACHE_KEY).catch(() => null)) as Fleet | null;
    if (cached) return cached;

    inFlight ??= (async () => {
      const url = `${FEED_URL}?key=${encodeURIComponent(key)}`;
      const res = await deps.fetch(url, { signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS) });
      if (!res.ok) throw new UpstreamError(`Bus Time answered ${res.status}`);
      const fleet = decodeFleet(new Uint8Array(await res.arrayBuffer()));
      // A failed cache write still answers this request from the fresh fetch.
      await cache.set(CACHE_KEY, fleet, { ttl: TTL_SECONDS, name: "bus fleet" }).catch(() => undefined);
      return fleet;
    })().finally(() => {
      inFlight = null;
    });
    return inFlight;
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
    return json(200, filterFleet(fleet, query), `public, max-age=0, s-maxage=${TTL_SECONDS}`);
  };
}

class UpstreamError extends Error {}
