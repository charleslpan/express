import GtfsRealtimeBindings from "gtfs-realtime-bindings";

const { FeedMessage } = GtfsRealtimeBindings.transit_realtime;

/** One bus as the endpoint returns it. */
export interface Bus {
  /** Bus Time vehicle id, such as `MTA NYCT_7582`. */
  id: string;
  /** GTFS route_id, such as `M15` or `M15+` (Select Bus Service). */
  route: string | null;
  /** GTFS direction_id, 0 or 1. */
  directionId: number | null;
  /** GTFS trip_id from the MTA bus timetables. */
  tripId: string | null;
  /** Always null: GTFS-RT vehicle positions carry no headsign. */
  headsign: null;
  lat: number;
  lon: number;
  /** Degrees clockwise from true north, or null where the feed has none. */
  bearing: number | null;
  /** Time of the GPS fix, in Unix seconds. */
  timestamp: number | null;
}

/** The whole fleet, decoded once and shared by every request. */
export interface Fleet {
  /** Feed header timestamp, in Unix seconds. */
  updatedAt: number | null;
  vehicles: Bus[];
}

export interface BBox {
  minLat: number;
  minLon: number;
  maxLat: number;
  maxLon: number;
}

export interface Query {
  bbox: BBox;
  /** Route ids to keep; null keeps every route. */
  routes: Set<string> | null;
}

// Wide enough for all five boroughs (about 0.4° by 0.55°) with room to spare,
// narrow enough that the endpoint stays a map query rather than a feed dump.
export const MAX_BBOX_SPAN_DEG = 1;
export const MAX_ROUTES = 50;
const ROUTE_ID = /^[A-Za-z0-9+\-]{1,16}$/;

function toNumber(value: number | { toNumber(): number } | null | undefined): number | null {
  if (value == null) return null;
  const n = typeof value === "number" ? value : value.toNumber();
  return n > 0 ? n : null;
}

/** Decodes a GTFS-RT vehicle positions feed into the compact fleet. */
export function decodeFleet(bytes: Uint8Array): Fleet {
  const feed = FeedMessage.decode(bytes);
  const vehicles: Bus[] = [];
  for (const entity of feed.entity) {
    const v = entity.vehicle;
    const pos = v?.position;
    if (!v || !pos || entity.isDeleted) continue;
    if (!Number.isFinite(pos.latitude) || !Number.isFinite(pos.longitude)) continue;
    if (pos.latitude === 0 && pos.longitude === 0) continue;
    vehicles.push({
      id: v.vehicle?.id || entity.id,
      route: v.trip?.routeId || null,
      directionId: v.trip?.directionId ?? null,
      tripId: v.trip?.tripId || null,
      headsign: null,
      lat: round(pos.latitude, 5),
      lon: round(pos.longitude, 5),
      bearing: pos.bearing != null && Number.isFinite(pos.bearing) ? round(pos.bearing, 1) : null,
      timestamp: toNumber(v.timestamp),
    });
  }
  return { updatedAt: toNumber(feed.header.timestamp), vehicles };
}

// GTFS-RT positions are float32, good to about a metre; 5 decimals keep that
// and drop the float32 noise.
function round(n: number, digits: number): number {
  const f = 10 ** digits;
  return Math.round(n * f) / f;
}

/** Parses and validates the query string; returns an error message on bad input. */
export function parseQuery(params: URLSearchParams): Query | { error: string } {
  const raw = params.get("bbox");
  if (!raw) return { error: "bbox is required: bbox=minLat,minLon,maxLat,maxLon" };
  const parts = raw.split(",");
  if (parts.length !== 4 || parts.some((p) => p.trim() === "")) {
    return { error: "bbox must be four numbers: minLat,minLon,maxLat,maxLon" };
  }
  const [minLat, minLon, maxLat, maxLon] = parts.map(Number);
  if (![minLat, minLon, maxLat, maxLon].every(Number.isFinite)) {
    return { error: "bbox must be four numbers: minLat,minLon,maxLat,maxLon" };
  }
  if (minLat < -90 || maxLat > 90 || minLon < -180 || maxLon > 180) {
    return { error: "bbox is out of range" };
  }
  if (minLat >= maxLat || minLon >= maxLon) {
    return { error: "bbox minimums must be below its maximums" };
  }
  if (maxLat - minLat > MAX_BBOX_SPAN_DEG || maxLon - minLon > MAX_BBOX_SPAN_DEG) {
    return { error: `bbox may span at most ${MAX_BBOX_SPAN_DEG}° in each direction` };
  }

  let routes: Set<string> | null = null;
  const rawRoutes = params.get("routes");
  if (rawRoutes != null) {
    const ids = rawRoutes.split(",").map((r) => r.trim()).filter(Boolean);
    if (ids.length === 0) return { error: "routes must list at least one route id" };
    if (ids.length > MAX_ROUTES) return { error: `routes may list at most ${MAX_ROUTES} route ids` };
    if (!ids.every((id) => ROUTE_ID.test(id))) return { error: "routes holds an invalid route id" };
    routes = new Set(ids);
  }
  return { bbox: { minLat, minLon, maxLat, maxLon }, routes };
}

/** Keeps the buses inside the bbox and, where given, on the listed routes. */
export function filterFleet(fleet: Fleet, { bbox, routes }: Query): Fleet {
  return {
    updatedAt: fleet.updatedAt,
    vehicles: fleet.vehicles.filter(
      (b) =>
        b.lat >= bbox.minLat &&
        b.lat <= bbox.maxLat &&
        b.lon >= bbox.minLon &&
        b.lon <= bbox.maxLon &&
        (routes === null || (b.route !== null && routes.has(b.route))),
    ),
  };
}
