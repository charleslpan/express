import { readFileSync } from "node:fs";
import GtfsRealtimeBindings from "gtfs-realtime-bindings";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { compactFleet, decodeFleet, expandFleet, filterFleet, parseQuery, type Bus, type Fleet } from "../lib/fleet.js";
import { CACHE_KEY, FEED_URL, createHandler, type FleetCache } from "../lib/handler.js";

// Twelve buses and the header from a real Bus Time feed, recorded on
// Nov 3, 2026 at 19:20 UTC: six in Lower Manhattan, two S79+ (Select Bus
// Service), and four elsewhere in the city.
const feed = readFileSync(new URL("./fixtures/bus-time-2026-11-03.pb", import.meta.url));
const FEED_TS = 1_793_733_639;
const NYC = "40.49,-74.26,40.92,-73.70";
const LOWER_MANHATTAN = "40.70,-74.02,40.72,-73.98";

describe("decodeFleet", () => {
  it("keeps every bus in the compact shape", () => {
    const fleet = decodeFleet(feed);
    expect(fleet.updatedAt).toBe(FEED_TS);
    expect(fleet.vehicles).toHaveLength(12);
    expect(fleet.vehicles[0]).toEqual({
      id: "MTA NYCT_9773",
      route: "M9",
      directionId: 1,
      // Interlined: the bus runs an M21 trip while signed as the M9.
      tripId: "MQ_D6-Weekday-082500_M21_203",
      headsign: null,
      lat: 40.71251,
      lon: -74.00925,
      bearing: 153.6,
      timestamp: 1_793_733_636,
    });
  });

  it("drops vehicles without a usable position and keeps unset fields null", () => {
    const { FeedMessage } = GtfsRealtimeBindings.transit_realtime;
    const bytes = FeedMessage.encode(
      FeedMessage.fromObject({
        header: { gtfsRealtimeVersion: "1.0", timestamp: FEED_TS },
        entity: [
          { id: "a", vehicle: { trip: { routeId: "M1" }, vehicle: { id: "a" } } },
          { id: "b", vehicle: { position: { latitude: 0, longitude: 0 }, vehicle: { id: "b" } } },
          { id: "c", tripUpdate: { trip: { routeId: "M2" }, stopTimeUpdate: [] } },
          { id: "d", vehicle: { trip: { routeId: "M3" }, position: { latitude: 40.7, longitude: -74 } } },
          { id: "e", vehicle: { trip: { routeId: "M4", directionId: 0 }, position: { latitude: 40.7, longitude: -74, bearing: 0 } } },
        ],
      }),
    ).finish();
    expect(decodeFleet(bytes).vehicles).toEqual([
      { id: "d", route: "M3", directionId: null, tripId: null, headsign: null, lat: 40.7, lon: -74, bearing: null, timestamp: null },
      { id: "e", route: "M4", directionId: 0, tripId: null, headsign: null, lat: 40.7, lon: -74, bearing: 0, timestamp: null },
    ]);
  });
});

describe("compactFleet", () => {
  it("round-trips the fleet in fewer bytes", () => {
    const fleet = decodeFleet(feed);
    const compact = compactFleet(fleet);
    expect(expandFleet(compact)).toEqual(fleet);
    expect(JSON.stringify(compact).length).toBeLessThan(JSON.stringify(fleet).length * 0.6);
  });
});

describe("parseQuery", () => {
  const q = (s: string) => parseQuery(new URLSearchParams(s));

  it("parses bbox and routes", () => {
    expect(q(`bbox=${LOWER_MANHATTAN}&routes=M15,M15%2B`)).toEqual({
      bbox: { minLat: 40.7, minLon: -74.02, maxLat: 40.72, maxLon: -73.98 },
      routes: new Set(["M15", "M15+"]),
    });
    expect(q(`bbox=${NYC}`)).toMatchObject({ routes: null });
  });

  it.each([
    ["", "required"],
    ["bbox=1,2,3", "four numbers"],
    ["bbox=40.7,-74,a,-73.9", "four numbers"],
    ["bbox=40.7,-74,,-73.9", "four numbers"],
    ["bbox=40.8,-74,40.7,-73.9", "below"],
    ["bbox=-91,-74,40.7,-73.9", "out of range"],
    ["bbox=39,-75,41,-73", "at most"],
    [`bbox=${NYC}&routes=`, "at least one"],
    [`bbox=${NYC}&routes=M1;drop`, "invalid"],
    [`bbox=${NYC}&routes=${Array.from({ length: 51 }, (_, i) => `M${i}`).join(",")}`, "at most 50"],
  ])("rejects %j", (s, msg) => {
    expect(q(s)).toEqual({ error: expect.stringContaining(msg) });
  });
});

describe("filterFleet", () => {
  const fleet = decodeFleet(feed);
  const run = (s: string) => {
    const query = parseQuery(new URLSearchParams(s));
    if ("error" in query) throw new Error(query.error);
    return filterFleet(fleet, query).vehicles.map((b) => b.id);
  };

  it("filters to the bbox", () => {
    expect(run(`bbox=${LOWER_MANHATTAN}`)).toEqual([
      "MTA NYCT_9773", "MTA NYCT_9708", "MTA NYCT_9723", "MTA NYCT_5359", "MTA NYCT_9717", "MTA NYCT_9718",
    ]);
    expect(run(`bbox=${NYC}`)).toHaveLength(12);
  });

  it("filters to the routes, matching route ids exactly", () => {
    expect(run(`bbox=${LOWER_MANHATTAN}&routes=M9`)).toEqual(["MTA NYCT_9773", "MTA NYCT_9708"]);
    expect(run(`bbox=${NYC}&routes=S79%2B,BX25`)).toEqual(["MTA NYCT_8583", "MTA NYCT_8580", "MTA NYCT_9770"]);
    expect(run(`bbox=${NYC}&routes=S79`)).toEqual([]);
  });

  it("keeps a whole-city response of a full fleet well under 4.5 MB", () => {
    const vehicles: Bus[] = Array.from({ length: 7_000 }, (_, i) => ({
      id: `MTA NYCT_${10_000 + i}`,
      route: `BX${i % 100}+`,
      directionId: 1,
      tripId: `MV_D6-Weekday-SDon-${100_000 + i}_BX${i % 100}_${i}`,
      headsign: null,
      lat: 40.712345,
      lon: -73.912345,
      bearing: 123.4,
      timestamp: 1_793_731_200,
    }));
    const body = JSON.stringify(filterFleet({ updatedAt: 1, vehicles }, parseQuery(new URLSearchParams(`bbox=${NYC}`)) as never));
    expect(body.length).toBeLessThan(2_000_000);
  });
});

/** A RuntimeCache stand-in that honours ttl against fake timers. */
function memoryCache() {
  const store = new Map<string, { value: unknown; expires: number }>();
  const reads = { count: 0 };
  const cache: FleetCache = {
    async get(key) {
      reads.count += 1;
      const hit = store.get(key);
      return hit && hit.expires > Date.now() ? structuredClone(hit.value) : null;
    },
    async set(key, value, opts) {
      store.set(key, { value: structuredClone(value), expires: Date.now() + (opts?.ttl ?? Infinity) * 1000 });
    },
  };
  return { cache, store, reads };
}

describe("handler", () => {
  let fetchMock: ReturnType<typeof vi.fn>;
  let mem: ReturnType<typeof memoryCache>;
  let key: string | undefined;

  const handler = () => createHandler({ cache: () => mem.cache, apiKey: () => key, fetch: fetchMock as never });
  const get = (h: ReturnType<typeof createHandler>, qs: string) => h(new Request(`https://x.test/api/vehicles/bus?${qs}`));

  beforeEach(() => {
    vi.useFakeTimers({ now: FEED_TS * 1000 });
    fetchMock = vi.fn(async () => new Response(feed));
    mem = memoryCache();
    key = "test-key";
  });

  it("answers filtered JSON with CDN caching", async () => {
    const res = await get(handler(), `bbox=${LOWER_MANHATTAN}`);
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("public, max-age=0, s-maxage=30, stale-while-revalidate=30");
    const body = (await res.json()) as Fleet;
    expect(body.updatedAt).toBe(FEED_TS);
    expect(body.vehicles.map((b) => b.route)).toEqual(["M9", "M9", "M20", "M15", "M55", "M22"]);
    expect(fetchMock).toHaveBeenCalledWith(`${FEED_URL}?key=test-key`, expect.anything());
  });

  it("fetches upstream once per 30 s across bboxes and instances", async () => {
    const a = handler();
    const b = handler(); // a second instance sharing the Runtime Cache
    await get(a, `bbox=${LOWER_MANHATTAN}`);
    await get(b, `bbox=${NYC}`);
    await get(a, `bbox=${NYC}&routes=M9`);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(mem.store.has(CACHE_KEY)).toBe(true);

    vi.advanceTimersByTime(31_000);
    await get(b, `bbox=${NYC}`);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("reads the Runtime Cache at most once per instance per 30 s", async () => {
    const a = handler();
    const b = handler();
    await get(a, `bbox=${NYC}`); // a misses, fetches, and keeps its copy
    expect(mem.reads.count).toBe(1);
    await get(b, `bbox=${NYC}`); // b reads a's copy from the Runtime Cache
    expect(mem.reads.count).toBe(2);
    vi.advanceTimersByTime(10_000);
    for (const h of [a, b, a, b]) await get(h, `bbox=${LOWER_MANHATTAN}`);
    expect(mem.reads.count).toBe(2);
    expect(fetchMock).toHaveBeenCalledTimes(1);

    vi.advanceTimersByTime(21_000); // both copies are 31 s old
    await get(a, `bbox=${NYC}`);
    expect(mem.reads.count).toBe(3);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("stores the compact fleet with its fetch time", async () => {
    await get(handler(), `bbox=${NYC}`);
    expect(mem.store.get(CACHE_KEY)?.value).toEqual({ fetchedAt: FEED_TS * 1000, fleet: compactFleet(decodeFleet(feed)) });
  });

  it("ignores a cached copy it can't read", async () => {
    mem.store.set(CACHE_KEY, { value: { updatedAt: 1, vehicles: [] }, expires: Infinity });
    const res = await get(handler(), `bbox=${NYC}`);
    expect(((await res.json()) as Fleet).vehicles).toHaveLength(12);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("shares one upstream fetch between concurrent misses", async () => {
    const h = handler();
    await Promise.all([get(h, `bbox=${NYC}`), get(h, `bbox=${LOWER_MANHATTAN}`), get(h, `bbox=${NYC}&routes=M15`)]);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("still answers when the Runtime Cache fails", async () => {
    mem.cache.get = async () => { throw new Error("cache down"); };
    mem.cache.set = async () => { throw new Error("cache down"); };
    const res = await get(handler(), `bbox=${NYC}`);
    expect(res.status).toBe(200);
  });

  it("rejects bad queries before touching upstream", async () => {
    const res = await get(handler(), "bbox=nope");
    expect(res.status).toBe(400);
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects other methods", async () => {
    const res = await handler()(new Request(`https://x.test/api/vehicles/bus?bbox=${NYC}`, { method: "POST" }));
    expect(res.status).toBe(405);
  });

  it("answers 503 without a key", async () => {
    key = undefined;
    const res = await get(handler(), `bbox=${NYC}`);
    expect(res.status).toBe(503);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("answers 502 on an upstream failure without leaking the key, and caches nothing", async () => {
    fetchMock.mockResolvedValueOnce(new Response("nope", { status: 403 }));
    const res = await get(handler(), `bbox=${NYC}`);
    expect(res.status).toBe(502);
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(await res.text()).not.toContain("test-key");
    expect(mem.store.size).toBe(0);
  });
});
