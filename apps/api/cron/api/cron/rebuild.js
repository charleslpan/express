// Daily Vercel Cron: rebuilds production without the build cache, so the
// MOTIS image downloads fresh MTA feeds and re-imports them. The image's own
// smoke test (motis/smoke-build.sh) gates the new deployment.
import { timingSafeEqual } from "node:crypto";

function authorized(request) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return false;
  const got = Buffer.from(request.headers.get("authorization") ?? "");
  const want = Buffer.from(`Bearer ${secret}`);
  return got.length === want.length && timingSafeEqual(got, want);
}

export async function GET(request) {
  if (!authorized(request)) {
    return Response.json({ ok: false, error: "unauthorized" }, { status: 401 });
  }
  if (!process.env.DEPLOY_HOOK_URL) {
    return Response.json({ ok: false, error: "DEPLOY_HOOK_URL is not set" }, { status: 500 });
  }

  const hook = new URL(process.env.DEPLOY_HOOK_URL);
  hook.searchParams.set("buildCache", "false");
  const res = await fetch(hook, { method: "POST" });
  const body = await res.json().catch(() => null);
  if (!res.ok) {
    console.error(`deploy hook answered ${res.status}`);
    return Response.json({ ok: false, error: `deploy hook answered ${res.status}` }, { status: 502 });
  }
  console.log(`deploy hook job ${body?.job?.id} ${body?.job?.state}`);
  return Response.json({ ok: true, job: body?.job ?? null });
}
