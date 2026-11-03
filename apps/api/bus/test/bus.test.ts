import { readFileSync } from "node:fs";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { decodeFleet, filterFleet, parseQuery, type Bus, type Fleet } from "../lib/fleet.js";
import { CACHE_KEY, FEED_URL, createHandler, type FleetCache } from "../lib/handler.js";

const feed = readFileSync(new URL("./fixtures/small.pb", import.meta.url));
const NYC = "40.49,-74.26,40.92,-73.70";
const LOWER_MANHATTAN = "40.70,-74.02,40.72,-73.98";

describe("decodeFleet", () => {
  it("keeps vehicles with a position, in the compact shape", () => {
    const fleet = decodeFleet(feed);
    expect(fleet.updatedAt).toBe(1_793_731_200);
    expect(fleet.vehicles.map((b) => b.id)).toEqual([
      "MTA NYCT_7582", "MTA NYCT_5911", "MTA NYCT_4022", "MTA NYCT_1301", "MTABC_3990",
    ]);
    expect(fleet.vehicles[0]).toEqual({
      id: "MTA NYCT_7582",
      route: "M15",
      directionId: 0,
      tripId: "OH_D6-Weekday-SDon-108500_M15_402",
      headsign: null,
      lat: 40.7075,
      lon: -74.0021,
      bearing: 212.4,
      timestamp: 1_793_731_188,
    });
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
    expect(run(`bbox=${LOWER_MANHATTAN}`)).toEqual(["MTA NYCT_7582", "MTA NYCT_5911"]);
    expect(run(`bbox=${NYC}`)).toHaveLength(5);
  });

  it("filters to the routes, matching route ids exactly", () => {
    expect(run(`bbox=${LOWER_MANHATTAN}&routes=M15`)).toEqual(["MTA NYCT_7582"]);
    expect(run(`bbox=${NYC}&routes=B44%2B,Q70%2B`)).toEqual(["MTA NYCT_1301", "MTABC_3990"]);
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
  const cache: FleetCache = {
    async get(key) {
      const hit = store.get(key);
      return hit && hit.expires > Date.now() ? structuredClone(hit.value) : null;
    },
    async set(key, value, opts) {
      store.set(key, { value: structuredClone(value), expires: Date.now() + (opts?.ttl ?? Infinity) * 1000 });
    },
  };
  return { cache, store };
}

describe("handler", () => {
  let fetchMock: ReturnType<typeof vi.fn>;
  let mem: ReturnType<typeof memoryCache>;
  let key: string | undefined;

  const handler = () => createHandler({ cache: () => mem.cache, apiKey: () => key, fetch: fetchMock as never });
  const get = (h: ReturnType<typeof createHandler>, qs: string) => h(new Request(`https://x.test/api/vehicles/bus?${qs}`));

  beforeEach(() => {
    vi.useFakeTimers({ now: 1_793_731_200_000 });
    fetchMock = vi.fn(async () => new Response(feed));
    mem = memoryCache();
    key = "test-key";
  });

  it("answers filtered JSON with CDN caching", async () => {
    const res = await get(handler(), `bbox=${LOWER_MANHATTAN}`);
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("public, max-age=0, s-maxage=30");
    const body = (await res.json()) as Fleet;
    expect(body.updatedAt).toBe(1_793_731_200);
    expect(body.vehicles.map((b) => b.route)).toEqual(["M15", "M15+"]);
    expect(fetchMock).toHaveBeenCalledWith(`${FEED_URL}?key=test-key`, expect.anything());
  });

  it("fetches upstream once per 30 s across bboxes and instances", async () => {
    const a = handler();
    const b = handler(); // a second instance sharing the Runtime Cache
    await get(a, `bbox=${LOWER_MANHATTAN}`);
    await get(b, `bbox=${NYC}`);
    await get(a, `bbox=${NYC}&routes=M42`);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(mem.store.has(CACHE_KEY)).toBe(true);

    vi.advanceTimersByTime(31_000);
    await get(b, `bbox=${NYC}`);
    expect(fetchMock).toHaveBeenCalledTimes(2);
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
