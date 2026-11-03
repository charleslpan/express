// Writes the GTFS-RT fixture the tests read, shaped like MTA Bus Time's
// vehicle positions feed (ids, route ids, and fields as Bus Time sends them).
// Run with `npm run fixture`. Replace small.pb with a real recording when one
// is available (see server/README.md).
import { writeFileSync } from "node:fs";
import GtfsRealtimeBindings from "gtfs-realtime-bindings";

const { FeedMessage } = GtfsRealtimeBindings.transit_realtime;
const HEADER_TS = 1_793_731_200; // Nov 3, 2026 18:40 UTC

function bus(id: string, route: string, dir: number, trip: string, lat: number, lon: number, bearing: number, age: number) {
  return {
    id,
    vehicle: {
      trip: { tripId: trip, routeId: route, directionId: dir, startDate: "20261103" },
      position: { latitude: lat, longitude: lon, bearing },
      timestamp: HEADER_TS - age,
      stopId: "401234",
      vehicle: { id },
    },
  };
}

const small = {
  header: { gtfsRealtimeVersion: "1.0", incrementality: 0, timestamp: HEADER_TS },
  entity: [
    // Lower Manhattan
    bus("MTA NYCT_7582", "M15", 0, "OH_D6-Weekday-SDon-108500_M15_402", 40.7075, -74.0021, 212.4, 12),
    bus("MTA NYCT_5911", "M15+", 1, "OH_D6-Weekday-SDon-109200_M15_701", 40.7139, -73.9921, 33.7, 25),
    // Midtown
    bus("MTA NYCT_4022", "M42", 0, "MQ_D6-Weekday-SDon-106000_M42_102", 40.7549, -73.9840, 90.0, 8),
    // Brooklyn
    bus("MTA NYCT_1301", "B44+", 1, "FP_D6-Weekday-SDon-107800_B44_601", 40.6501, -73.9496, 359.2, 40),
    // Queens, MTA Bus Company
    bus("MTABC_3990", "Q70+", 0, "LGA_D6-Weekday-SDon-108100_Q70_301", 40.7465, -73.8913, 270.5, 5),
    // No position: dropped
    { id: "MTA NYCT_0001", vehicle: { trip: { routeId: "M1" }, timestamp: HEADER_TS, vehicle: { id: "MTA NYCT_0001" } } },
    // A trip update, not a vehicle: dropped
    { id: "tu-1", tripUpdate: { trip: { tripId: "x", routeId: "M2" }, stopTimeUpdate: [] } },
  ],
};

const dir = new URL("./fixtures/", import.meta.url);
writeFileSync(new URL("small.pb", dir), FeedMessage.encode(FeedMessage.fromObject(small)).finish());
