// GET /api/cron/rebuild: the daily Vercel Cron target. See apps/api/README.md,
// "Nightly rebuild".
import { createHandler } from "../../lib/rebuild.js";

const handle = createHandler({
  cronSecret: () => process.env.CRON_SECRET,
  hookUrl: () => process.env.DEPLOY_HOOK_URL,
  fetch,
});

export default { fetch: handle };
