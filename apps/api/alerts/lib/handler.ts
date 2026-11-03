import { indexAlerts, parseLines, selectLines, type AlertIndex } from "./alerts.js";

/** The MTA's GTFS-RT alert feeds as JSON, which carry the MTA's alert type (no key needed). */
export const FEED_URLS = {
  subway: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/camsys%2Fsubway-alerts.json",
  bus: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/camsys%2Fbus-alerts.json",
} as const;
export const CACHE_KEY = "mta-alerts:index:v1";
export const TTL_SECONDS = 60;
const UPSTREAM_TIMEOUT_MS = 10_000;

/** The part of Vercel's RuntimeCache this handler uses. */
export interface AlertCache {
  get(key: string): Promise<unknown | null>;
  set(key: string, value: unknown, options?: { ttl?: number; name?: string }): Promise<void>;
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
  // Requests that miss the Runtime Cache on the same instance share one fetch.
  let inFlight: Promise<AlertIndex> | null = null;
  // Log each unknown MTA alert type once per instance, not on every refresh.
  const warned = new Set<string>();

  async function fetchFeed(url: string): Promise<unknown> {
    const res = await deps.fetch(url, { signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS) });
    if (!res.ok) throw new Error(`MTA alerts answered ${res.status}`);
    return res.json();
  }

  async function loadIndex(): Promise<AlertIndex> {
    const cache = deps.cache();
    const cached = (await cache.get(CACHE_KEY).catch(() => null)) as AlertIndex | null;
    if (cached) return cached;

    inFlight ??= (async () => {
      const [subway, bus] = await Promise.all([fetchFeed(FEED_URLS.subway), fetchFeed(FEED_URLS.bus)]);
      const index = indexAlerts(subway, bus, (type) => {
        const key = type ?? "(none)";
        if (warned.has(key)) return;
        warned.add(key);
        console.warn(`unknown MTA alert type, mapped to the fallback: ${key}`);
      });
      // A failed cache write still answers this request from the fresh fetch.
      await cache.set(CACHE_KEY, index, { ttl: TTL_SECONDS, name: "mta alerts" }).catch(() => undefined);
      return index;
    })().finally(() => {
      inFlight = null;
    });
    return inFlight;
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
    return json(200, selectLines(index, lines), `public, max-age=0, s-maxage=${TTL_SECONDS}`);
  };
}
