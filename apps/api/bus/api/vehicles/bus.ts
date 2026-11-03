// GET /api/vehicles/bus?bbox=minLat,minLon,maxLat,maxLon[&routes=M15,B44+]
// Live bus GPS from MTA Bus Time, filtered to a bounding box. See apps/api/README.md.
import { getCache } from "@vercel/functions";
import { createHandler } from "../../lib/handler.js";

const handle = createHandler({
  cache: () => getCache({ namespace: "express-bus" }),
  apiKey: () => process.env.MTA_BUS_TIME_KEY,
  fetch,
});

export default { fetch: handle };
