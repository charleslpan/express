// GET /api/cron/rebuild: the daily Vercel Cron target. See apps/api/README.md,
// "Nightly rebuild".
import { pruneImages } from "../../lib/prune.js";
import { createHandler } from "../../lib/rebuild.js";

// charlespan's projects (Hobby); see apps/api/AGENTS.md.
const TEAM_ID = "team_DQArotHEGEevMkHtaaehgB2F";

const handle = createHandler({
  cronSecret: () => process.env.CRON_SECRET,
  hookUrl: () => process.env.DEPLOY_HOOK_URL,
  fetch,
  prune: async () => {
    const token = process.env.VERCEL_API_TOKEN;
    if (!token) throw new Error("VERCEL_API_TOKEN is not set");
    return pruneImages({
      token,
      teamId: TEAM_ID,
      projectId: process.env.VERCEL_PROJECT_ID ?? "express",
      deploymentId: process.env.VERCEL_DEPLOYMENT_ID,
      fetch,
      log: console,
    });
  },
});

export default { fetch: handle };
