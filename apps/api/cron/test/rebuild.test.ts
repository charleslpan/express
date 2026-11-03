import { describe, expect, it, vi } from "vitest";
import { createHandler } from "../lib/rebuild.js";

const HOOK = "https://api.vercel.com/v1/integrations/deploy/prj_test/hook";
const URL_ = "https://example.test/api/cron/rebuild";

function setup(env: { secret?: string; hook?: string } = { secret: "s3cret", hook: HOOK }) {
  const fetch = vi.fn(async () => Response.json({ job: { id: "j1", state: "PENDING" } }));
  const handle = createHandler({ cronSecret: () => env.secret, hookUrl: () => env.hook, fetch });
  return { fetch, handle };
}

const get = (auth?: string, url = URL_) =>
  new Request(url, { headers: auth ? { authorization: auth } : {} });

describe("rebuild", () => {
  it("rejects a missing or wrong token without calling the hook", async () => {
    const { fetch, handle } = setup();
    expect((await handle(get())).status).toBe(401);
    expect((await handle(get("Bearer nope"))).status).toBe(401);
    expect(fetch).not.toHaveBeenCalled();
  });

  it("rejects every request when CRON_SECRET is unset", async () => {
    const { fetch, handle } = setup({ hook: HOOK });
    expect((await handle(get("Bearer "))).status).toBe(401);
    expect(fetch).not.toHaveBeenCalled();
  });

  it("POSTs the hook without build cache and returns its job", async () => {
    const { fetch, handle } = setup();
    const res = await handle(get("Bearer s3cret"));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, job: { id: "j1", state: "PENDING" } });
    expect(fetch).toHaveBeenCalledOnce();
    const [url, init] = fetch.mock.calls[0] as unknown as [URL, RequestInit];
    expect(url.toString()).toBe(`${HOOK}?buildCache=false`);
    expect(init.method).toBe("POST");
  });

  it("reports a missing hook URL and a failing hook", async () => {
    expect((await setup({ secret: "s3cret" }).handle(get("Bearer s3cret"))).status).toBe(500);
    const { fetch, handle } = setup();
    fetch.mockResolvedValueOnce(new Response("nope", { status: 404 }));
    expect((await handle(get("Bearer s3cret"))).status).toBe(502);
  });

  it("answers 404 off its path and 405 for other methods", async () => {
    const { handle } = setup();
    expect((await handle(get("Bearer s3cret", "https://example.test/api/cron/other"))).status).toBe(404);
    expect((await handle(new Request(URL_, { method: "POST" }))).status).toBe(405);
  });
});
