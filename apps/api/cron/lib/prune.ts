// Prunes old images from the project's `motis` Container Registry repository,
// which every build pushes to and nothing else cleans up. Runs before the
// nightly rebuild so its push has room. See apps/api/README.md, "Old
// deployments and images".
const API = "https://api.vercel.com";
export const REPOSITORY = "motis";
export const KEEP_NEWEST = 5;
// Untagged images (an index's platform manifests and attestations) are pushed
// seconds before the tagged image they belong to; this margin keeps them with it.
const UNTAGGED_MARGIN_MS = 60 * 60 * 1000;
const MAX_PAGES = 20;

export interface Image {
  id: string;
  createdAt: string;
  tags: string[];
}

export interface Production {
  /**
   * Tags production's image may carry: each build tags its image with the
   * first 12 characters of its commit SHA (`motis:bdcc5b5b7c92`), so these are
   * production's commit SHAs, plus its deployment ids in case that changes.
   */
  tags: string[];
  /** When production's deployment was created, in ms; its image was pushed after that. */
  createdAt: number;
}

export interface Plan {
  keep: Image[];
  remove: Image[];
}

/**
 * Chooses which images to keep: production's own image (by tag), every image
 * pushed since production's deployment was created (production's image among
 * them even if its tag is not found), and the newest `keepNewest` images.
 * Older untagged images (an earlier build of a commit whose tag moved to a
 * rebuild, or an index's children) go only when they are more than an hour
 * older than every tagged image kept.
 */
export function planPrune(images: Image[], production: Production, keepNewest = KEEP_NEWEST): Plan {
  const time = (image: Image) => Date.parse(image.createdAt);
  const newestFirst = [...images].sort((a, b) => time(b) - time(a));
  const kept = new Set<Image>(newestFirst.slice(0, keepNewest));
  for (const image of newestFirst) {
    const isProduction = image.tags.some((tag) => production.tags.includes(tag));
    // An unparseable date compares false; keep such images rather than guess.
    if (isProduction || !(time(image) < production.createdAt)) kept.add(image);
  }
  const keptTimes = [...kept].filter((image) => image.tags.length > 0).map(time);
  const cutoff = Math.min(production.createdAt, ...keptTimes) - UNTAGGED_MARGIN_MS;
  for (const image of newestFirst) {
    if (image.tags.length === 0 && !(time(image) < cutoff)) kept.add(image);
  }
  return {
    keep: newestFirst.filter((image) => kept.has(image)),
    remove: newestFirst.filter((image) => !kept.has(image)),
  };
}

export interface PruneDeps {
  token: string;
  teamId: string;
  projectId: string;
  /** The deployment this function runs in (production, when Vercel Cron calls it) and its commit. */
  deploymentId: string | undefined;
  commitSha: string | undefined;
  fetch: typeof fetch;
  log: Pick<Console, "log" | "warn">;
}

export interface PruneResult {
  kept: number;
  deleted: number;
  failed: number;
}

async function api<T>(deps: PruneDeps, method: string, path: string, query: Record<string, string> = {}): Promise<T> {
  const url = new URL(path, API);
  url.searchParams.set("teamId", deps.teamId);
  for (const [key, value] of Object.entries(query)) url.searchParams.set(key, value);
  const res = await deps.fetch(url, {
    method,
    headers: { authorization: `Bearer ${deps.token}` },
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) throw new Error(`${method} ${url.pathname} answered ${res.status}`);
  return (await res.json().catch(() => null)) as T;
}

async function productionOf(deps: PruneDeps): Promise<Production> {
  const project = await api<{
    targets?: { production?: { id?: string; createdAt?: number; meta?: { githubCommitSha?: string } } };
  }>(
    deps,
    "GET",
    `/v9/projects/${encodeURIComponent(deps.projectId)}`,
  );
  const target = project?.targets?.production;
  if (!target?.id || typeof target.createdAt !== "number") throw new Error("project has no production deployment");
  const ids = [target.id, deps.deploymentId];
  const shas = [target.meta?.githubCommitSha, deps.commitSha];
  const tags = [...ids, ...shas, ...shas.map((sha) => sha?.slice(0, 12))].filter((tag): tag is string => !!tag);
  return { tags: [...new Set(tags)], createdAt: target.createdAt };
}

async function listImages(deps: PruneDeps): Promise<Image[]> {
  const images: Image[] = [];
  let cursor: string | undefined;
  for (let page = 0; page < MAX_PAGES; page++) {
    const query: Record<string, string> = { projectId: deps.projectId, limit: "100" };
    if (cursor) query.cursor = cursor;
    const body = await api<{ images?: Image[]; nextCursor?: string }>(
      deps,
      "GET",
      `/v1/vcr/repository/${REPOSITORY}/images`,
      query,
    );
    images.push(...(body?.images ?? []));
    cursor = body?.nextCursor;
    if (!cursor) return images;
  }
  throw new Error(`more than ${MAX_PAGES} pages of images`);
}

/** Deletes old `motis` images. Throws if it cannot tell what production uses. */
export async function pruneImages(deps: PruneDeps): Promise<PruneResult> {
  const production = await productionOf(deps);
  const images = await listImages(deps);
  const { keep, remove } = planPrune(images, production);
  let deleted = 0;
  let failed = 0;
  for (const image of remove) {
    try {
      await api(deps, "DELETE", `/v1/vcr/repository/${REPOSITORY}/images/${encodeURIComponent(image.id)}`, {
        projectId: deps.projectId,
      });
      deleted++;
    } catch (error) {
      failed++;
      deps.log.warn(`prune: could not delete ${image.id}: ${(error as Error).message}`);
    }
  }
  deps.log.log(
    `prune: ${REPOSITORY} had ${images.length} images; kept ${keep.length}, deleted ${deleted}` +
      (failed ? `, ${failed} failed` : "") +
      ` (production ${production.tags[0]})`,
  );
  return { kept: keep.length, deleted, failed };
}
