import { describe, expect, it, vi } from "vitest";
import { type Image, planPrune, pruneImages } from "../lib/prune.js";
import { createHandler } from "../lib/rebuild.js";

const HOUR = 60 * 60 * 1000;
const T0 = Date.parse("2026-11-05T09:00:00.000Z");
const at = (hoursAgo: number) => new Date(T0 - hoursAgo * HOUR).toISOString();
const image = (id: string, hoursAgo: number, tags = [`dpl_${id}`]): Image => ({ id, createdAt: at(hoursAgo), tags });
const ids = (images: Image[]) => images.map((i) => i.id);

// Ten builds, one a day, newest first: img0 (0 h ago) … img9 (216 h ago).
const daily = Array.from({ length: 10 }, (_, n) => image(`img${n}`, n * 24));

describe("planPrune", () => {
  it("keeps the newest five and production's image, oldest first to go", () => {
    const production = { deploymentIds: ["dpl_img7"], createdAt: T0 - 168 * HOUR - 60_000 };
    const plan = planPrune(daily, production);
    // Everything since production's deployment was created stays, too.
    expect(ids(plan.keep)).toEqual(["img0", "img1", "img2", "img3", "img4", "img5", "img6", "img7"]);
    expect(ids(plan.remove)).toEqual(["img8", "img9"]);
  });

  it("keeps production's image by tag even when it predates its deployment's createdAt", () => {
    const production = { deploymentIds: ["dpl_img9"], createdAt: T0 };
    const plan = planPrune(daily, production);
    expect(ids(plan.keep)).toEqual(["img0", "img1", "img2", "img3", "img4", "img9"]);
    expect(ids(plan.remove)).toEqual(["img5", "img6", "img7", "img8"]);
  });

  it("keeps production's image by time when its tag is not found", () => {
    const production = { deploymentIds: ["dpl_unknown"], createdAt: T0 - 192 * HOUR - 60_000 };
    expect(ids(planPrune(daily, production).remove)).toEqual(["img9"]);
  });

  it("keeps the deployment it runs in as well as the project's production target", () => {
    const production = { deploymentIds: ["dpl_img0", "dpl_img8"], createdAt: T0 };
    expect(ids(planPrune(daily, production).remove)).toEqual(["img5", "img6", "img7", "img9"]);
  });

  it("deletes untagged images only when older than everything kept", () => {
    const images = [
      ...daily.slice(0, 6),
      image("child-of-img4", 96.01, []), // pushed just before img4
      image("orphan", 200, []),
    ];
    const plan = planPrune(images, { deploymentIds: ["dpl_img0"], createdAt: T0 });
    expect(ids(plan.keep)).toContain("child-of-img4");
    expect(ids(plan.remove)).toEqual(["img5", "orphan"]);
  });

  it("keeps everything when there is nothing old", () => {
    const plan = planPrune(daily.slice(0, 3), { deploymentIds: ["dpl_img2"], createdAt: T0 - 48 * HOUR });
    expect(plan.remove).toEqual([]);
  });

  it("keeps an image whose date cannot be read", () => {
    const images = [...daily, { id: "odd", createdAt: "not a date", tags: ["x"] }];
    const plan = planPrune(images, { deploymentIds: ["dpl_img0"], createdAt: T0 });
    expect(ids(plan.keep)).toContain("odd");
  });
});

function mockApi(images: Image[], options: { project?: unknown; failList?: boolean; failDelete?: string } = {}) {
  const deleted: string[] = [];
  const fetch = vi.fn(async (input: URL | string | Request, init?: RequestInit) => {
    const url = new URL(input.toString());
    expect(url.searchParams.get("teamId")).toBe("team_test");
    expect(new Headers(init?.headers).get("authorization")).toBe("Bearer tok");
    if (url.pathname === "/v9/projects/prj_test") {
      return Response.json(options.project ?? { targets: { production: { id: "dpl_img0", createdAt: T0 } } });
    }
    if (url.pathname === "/v1/vcr/repository/motis/images" && init?.method === "GET") {
      if (options.failList) return new Response("nope", { status: 500 });
      expect(url.searchParams.get("projectId")).toBe("prj_test");
      // Two pages, to exercise the cursor.
      const page = url.searchParams.get("cursor") === "p2" ? images.slice(4) : images.slice(0, 4);
      return Response.json({ images: page, ...(url.searchParams.get("cursor") ? {} : { nextCursor: "p2" }) });
    }
    const match = /^\/v1\/vcr\/repository\/motis\/images\/(.+)$/.exec(url.pathname);
    if (match && init?.method === "DELETE") {
      expect(url.searchParams.get("projectId")).toBe("prj_test");
      const id = match[1] ?? "";
      if (id === options.failDelete) return new Response("nope", { status: 500 });
      deleted.push(id);
      return Response.json(null, { status: 202 });
    }
    return new Response("unexpected", { status: 404 });
  });
  const log = { log: vi.fn(), warn: vi.fn() };
  const deps = { token: "tok", teamId: "team_test", projectId: "prj_test", deploymentId: "dpl_img0", fetch, log };
  return { deps, deleted, log, fetch };
}

describe("pruneImages", () => {
  it("lists every page, deletes the old images, and logs the counts", async () => {
    const { deps, deleted, log } = mockApi(daily);
    expect(await pruneImages(deps)).toEqual({ kept: 5, deleted: 5, failed: 0 });
    expect(deleted).toEqual(["img5", "img6", "img7", "img8", "img9"]);
    expect(log.log).toHaveBeenCalledWith(expect.stringContaining("kept 5, deleted 5"));
    expect(JSON.stringify(log.log.mock.calls)).not.toContain("tok");
  });

  it("counts a failed delete and goes on", async () => {
    const { deps, deleted, log } = mockApi(daily, { failDelete: "img6" });
    expect(await pruneImages(deps)).toEqual({ kept: 5, deleted: 4, failed: 1 });
    expect(deleted).toEqual(["img5", "img7", "img8", "img9"]);
    expect(log.warn).toHaveBeenCalledOnce();
  });

  it("deletes nothing when production is unknown or the list fails", async () => {
    const noProd = mockApi(daily, { project: { targets: {} } });
    await expect(pruneImages(noProd.deps)).rejects.toThrow("no production deployment");
    expect(noProd.deleted).toEqual([]);
    const failing = mockApi(daily, { failList: true });
    await expect(pruneImages(failing.deps)).rejects.toThrow("answered 500");
    expect(failing.deleted).toEqual([]);
  });
});

describe("rebuild with prune", () => {
  const HOOK = "https://api.vercel.com/v1/integrations/deploy/prj_test/hook";
  const get = () =>
    new Request("https://example.test/api/cron/rebuild", { headers: { authorization: "Bearer s3cret" } });

  it("prunes before calling the hook", async () => {
    const order: string[] = [];
    const fetch = vi.fn(async () => {
      order.push("hook");
      return Response.json({ job: { id: "j1", state: "PENDING" } });
    });
    const prune = vi.fn(async () => order.push("prune"));
    const handle = createHandler({ cronSecret: () => "s3cret", hookUrl: () => HOOK, fetch, prune });
    expect((await handle(get())).status).toBe(200);
    expect(order).toEqual(["prune", "hook"]);
  });

  it("warns and still rebuilds when pruning fails", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const fetch = vi.fn(async () => Response.json({ job: { id: "j1", state: "PENDING" } }));
    const prune = vi.fn(async () => {
      throw new Error("VERCEL_API_TOKEN is not set");
    });
    const handle = createHandler({ cronSecret: () => "s3cret", hookUrl: () => HOOK, fetch, prune });
    expect((await handle(get())).status).toBe(200);
    expect(fetch).toHaveBeenCalledOnce();
    expect(warn).toHaveBeenCalledWith("prune skipped: VERCEL_API_TOKEN is not set");
    warn.mockRestore();
  });
});
