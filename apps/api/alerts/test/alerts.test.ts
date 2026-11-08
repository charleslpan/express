import { readFileSync } from "node:fs";
import { gunzipSync } from "node:zlib";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { table } from "../lib/alert-types.js";
import { indexAlerts, mapAlertType, parseLines, selectLines, MAX_LINES } from "../lib/alerts.js";
import { CACHE_KEY, FEED_URLS, STALE_SECONDS, TTL_SECONDS, createHandler, type AlertCache } from "../lib/handler.js";

// The MTA's subway and bus alert feeds (GTFS-RT JSON), recorded on Nov 3, 2026 at about 21:30 UTC.
const recorded = (name: string): unknown =>
  JSON.parse(gunzipSync(readFileSync(new URL(`./fixtures/${name}-2026-11-03.json.gz`, import.meta.url))).toString());
const subway = recorded("subway-alerts");
const bus = recorded("bus-alerts");

describe("alert-type table", () => {
  it("is the motis adapter's table", () => {
    const canonical = new URL("../../motis/adapter/alert_types.json", import.meta.url);
    expect(table).toEqual(JSON.parse(readFileSync(canonical, "utf8")));
  });

  it("covers every alert type in the recorded feeds", () => {
    const unknown: (string | null)[] = [];
    const index = indexAlerts(subway, bus, (t) => unknown.push(t));
    expect(unknown).toEqual([]);
    const seen = new Set(Object.values(index.lines).flat().map((a) => a.type));
    expect(seen.size).toBeGreaterThan(15);
  });

  it("maps types, planned work, and unknown types", () => {
    expect(mapAlertType("Delays")).toEqual({ effect: "SIGNIFICANT_DELAYS", cause: "UNKNOWN_CAUSE", severity: "WARNING", known: true });
    expect(mapAlertType("Planned - Part Suspended")).toEqual({ effect: "NO_SERVICE", cause: "MAINTENANCE", severity: "SEVERE", known: true });
    expect(mapAlertType("Boarding Change").effect).toBe("STOP_MOVED");
    expect(mapAlertType("Alien Invasion")).toEqual({ effect: "OTHER_EFFECT", cause: "UNKNOWN_CAUSE", severity: "INFO", known: false });
    expect(mapAlertType(null).known).toBe(false);
    expect(mapAlertType("toString").known).toBe(false);
  });
});

describe("indexAlerts", () => {
  const index = indexAlerts(subway, bus);

  it("files a multi-line alert under each line with only that line's stops", () => {
    const delays = index.lines["2"]?.find((a) => a.id === "lmm:alert:274734:26");
    expect(delays).toEqual({
      id: "lmm:alert:274734:26",
      type: "Delays",
      effect: "SIGNIFICANT_DELAYS",
      cause: "UNKNOWN_CAUSE",
      severity: "WARNING",
      activePeriods: [{ start: 1_793_740_456, end: 1_793_742_540 }],
      header:
        "Wakefield-241 St-bound [2] and Eastchester-Dyre Av-bound [5] trains are running with delays after we EMS assisted someone in need on a train at E 180 St.",
      description: null,
      affected: [{ stopId: null, directionId: null }],
    });
    expect(index.lines["5"]?.some((a) => a.id === "lmm:alert:274734:26")).toBe(true);
  });

  it("keeps stops and directions", () => {
    const withStops = index.lines["C"]?.find((a) => a.affected.some((x) => x.stopId === "A24"));
    expect(withStops?.affected.every((x) => x.stopId !== null)).toBe(true);
    const directions = new Set(index.lines["C"]?.flatMap((a) => a.affected.map((x) => x.directionId)));
    expect(directions).toEqual(new Set([0, 1, null]));
  });

  it("keeps future and open-ended alerts", () => {
    const all = Object.values(index.lines).flat();
    const now = 1_793_741_400; // when the feeds were recorded
    expect(all.some((a) => a.activePeriods.every((p) => p.start !== null && p.start > now))).toBe(true);
    expect(all.some((a) => a.activePeriods.some((p) => p.end === null))).toBe(true);
  });

  it("reads bus lines and English text", () => {
    const bm1 = index.lines["BM1"]?.find((a) => a.id === "lmm:alert:274725:31");
    expect(bm1?.type).toBe("Detour");
    expect(bm1?.effect).toBe("DETOUR");
    expect(bm1?.affected).toEqual([{ stopId: null, directionId: null }]);
    expect(bm1?.description).toMatch(/^Brooklyn-bound BM1, BM2, BM3, and BM4 buses will not stop at:\n/);
    expect(index.updatedAt.subway).toBeGreaterThan(1_793_000_000);
    expect(index.updatedAt.bus).toBeGreaterThan(1_793_000_000);
  });
});

describe("parseLines and selectLines", () => {
  it("reads + literally and %2B too", () => {
    expect(parseLines("?lines=A,C,M15+")).toEqual(["A", "C", "M15+"]);
    expect(parseLines("?x=1&lines=B44%2B,%20SI,A")).toEqual(["B44+", "SI", "A"]);
    // What the Function sees on Vercel for `lines=M15+,A`: the bare + arrives as %20.
    expect(parseLines("?lines=M15%20,A")).toEqual(["M15+", "A"]);
  });

  it("rejects bad queries", () => {
    expect(parseLines("")).toHaveProperty("error");
    expect(parseLines("?lines=")).toHaveProperty("error");
    expect(parseLines("?lines=A;B")).toHaveProperty("error");
    expect(parseLines("?lines=%E0%A4%A")).toHaveProperty("error");
    expect(parseLines(`?lines=${Array.from({ length: MAX_LINES + 1 }, (_, i) => `M${i}`).join(",")}`)).toHaveProperty("error");
  });

  it("answers each requested line, an empty list where it has none", () => {
    const out = selectLines(indexAlerts(subway, bus), ["A", "M15+", "Z9", "toString"]);
    expect(Object.keys(out.lines)).toEqual(["A", "M15+", "Z9", "toString"]);
    expect(out.lines["A"]?.length).toBeGreaterThan(0);
    expect(out.lines["Z9"]).toEqual([]);
    expect(out.lines["toString"]).toEqual([]);
    expect(out.lines["A"]?.every((a) => a.affected.length > 0)).toBe(true);
  });
});

describe("handler", () => {
  let store: Map<string, unknown>;
  let cache: AlertCache;
  let fetchMock: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    store = new Map();
    cache = {
      get: vi.fn(async (k: string) => store.get(k) ?? null),
      set: vi.fn(async (k: string, v: unknown) => void store.set(k, structuredClone(v))),
    };
    fetchMock = vi.fn(async (url: string) =>
      Response.json(url === FEED_URLS.subway ? subway : url === FEED_URLS.bus ? bus : null),
    );
  });

  const handler = () => createHandler({ cache: () => cache, fetch: fetchMock as unknown as typeof fetch });
  const get = (h: ReturnType<typeof handler>, q: string) => h(new Request(`https://x.test/api/alerts${q}`));

  it("answers the requested lines and caches both feeds for a minute", async () => {
    const h = handler();
    const res = await get(h, "?lines=L,BM1");
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe(
      `public, max-age=0, s-maxage=${TTL_SECONDS}, stale-while-revalidate=${STALE_SECONDS}`,
    );
    const body = (await res.json()) as ReturnType<typeof selectLines>;
    expect(Object.keys(body.lines)).toEqual(["L", "BM1"]);
    expect(body.lines["BM1"]?.some((a) => a.id === "lmm:alert:274725:31")).toBe(true);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(cache.set).toHaveBeenCalledWith(CACHE_KEY, expect.anything(), { ttl: 60, name: "mta alerts" });

    await get(handler(), "?lines=A");
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("reads the Runtime Cache at most once per instance per minute", async () => {
    vi.useFakeTimers({ now: Date.UTC(2026, 10, 3, 21, 30) });
    try {
      const a = handler();
      const b = handler();
      await get(a, "?lines=A"); // a misses, fetches, and keeps its copy
      await get(b, "?lines=A"); // b reads a's copy from the Runtime Cache
      expect(cache.get).toHaveBeenCalledTimes(2);
      expect(store.get(CACHE_KEY)).toMatchObject({ fetchedAt: Date.now() });
      vi.advanceTimersByTime(30_000);
      for (const h of [a, b, a, b]) await get(h, "?lines=C");
      expect(cache.get).toHaveBeenCalledTimes(2);
      expect(fetchMock).toHaveBeenCalledTimes(2);

      vi.advanceTimersByTime(31_000); // both copies are 61 s old
      await get(b, "?lines=A");
      expect(cache.get).toHaveBeenCalledTimes(3);
      expect(fetchMock).toHaveBeenCalledTimes(4);
    } finally {
      vi.useRealTimers();
    }
  });

  it("shares one fetch between concurrent misses", async () => {
    const h = handler();
    await Promise.all([get(h, "?lines=A"), get(h, "?lines=C")]);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("answers 400, 405, and 502 without caching", async () => {
    const h = handler();
    const bad = await get(h, "?lines=");
    expect(bad.status).toBe(400);
    expect(bad.headers.get("cache-control")).toBe("no-store");
    expect((await h(new Request("https://x.test/api/alerts?lines=A", { method: "POST" }))).status).toBe(405);

    fetchMock.mockImplementation(async () => new Response("down", { status: 503 }));
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const down = await get(h, "?lines=A");
    expect(down.status).toBe(502);
    expect(down.headers.get("cache-control")).toBe("no-store");
    expect(store.size).toBe(0);
  });
});
