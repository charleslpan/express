// Rebuilds production without the build cache, so the MOTIS image downloads
// fresh MTA feeds and re-imports them. The image's own smoke test
// (motis/smoke-build.sh) gates the new deployment. Old `motis` images are
// pruned first (lib/prune.ts), so the build has room to push its own.
import { timingSafeEqual } from "node:crypto";

export const PATH = "/api/cron/rebuild";

export interface RebuildDeps {
  cronSecret: () => string | undefined;
  hookUrl: () => string | undefined;
  fetch: typeof fetch;
  /** Frees registry space before the build. Its failure never stops the rebuild. */
  prune?: () => Promise<unknown>;
}

function authorized(request: Request, secret: string | undefined): boolean {
  if (!secret) return false;
  const got = Buffer.from(request.headers.get("authorization") ?? "");
  const want = Buffer.from(`Bearer ${secret}`);
  return got.length === want.length && timingSafeEqual(got, want);
}

export function createHandler(deps: RebuildDeps): (request: Request) => Promise<Response> {
  return async (request) => {
    if (new URL(request.url).pathname !== PATH) return new Response("not found", { status: 404 });
    if (request.method !== "GET") return new Response("method not allowed", { status: 405 });
    if (!authorized(request, deps.cronSecret())) {
      return Response.json({ ok: false, error: "unauthorized" }, { status: 401 });
    }
    const hookUrl = deps.hookUrl();
    if (!hookUrl) {
      return Response.json({ ok: false, error: "DEPLOY_HOOK_URL is not set" }, { status: 500 });
    }

    if (deps.prune) {
      try {
        await deps.prune();
      } catch (error) {
        console.warn(`prune skipped: ${(error as Error).message}`);
      }
    }

    const hook = new URL(hookUrl);
    hook.searchParams.set("buildCache", "false");
    const res = await deps.fetch(hook, { method: "POST" });
    const body = (await res.json().catch(() => null)) as { job?: { id?: string; state?: string } } | null;
    if (!res.ok) {
      console.error(`deploy hook answered ${res.status}`);
      return Response.json({ ok: false, error: `deploy hook answered ${res.status}` }, { status: 502 });
    }
    console.log(`deploy hook job ${body?.job?.id} ${body?.job?.state}`);
    return Response.json({ ok: true, job: body?.job ?? null });
  };
}
