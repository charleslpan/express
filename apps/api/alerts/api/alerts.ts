// GET /api/alerts?lines=A,C,M15+
// MTA subway and bus service alerts per line, with the standard effect, cause, and severity. See apps/api/README.md.
import { getCache } from "@vercel/functions";
import { createHandler } from "../lib/handler.js";

const handle = createHandler({
  cache: () => getCache({ namespace: "express-alerts" }),
  fetch,
});

export default { fetch: handle };
