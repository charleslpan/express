import { table } from "./alert-types.js";

/** GTFS-RT alert effect, as MOTIS names it. */
export type Effect = (typeof table.types)[keyof typeof table.types]["effect"] | typeof table.fallback.effect;
/** GTFS-RT alert cause; the MTA's types tell only planned work apart. */
export type Cause = typeof table.plannedCause | "UNKNOWN_CAUSE";
/** GTFS-RT alert severity level. */
export type Severity = (typeof table.types)[keyof typeof table.types]["severity"] | typeof table.fallback.severity;

export interface Period {
  /** Unix seconds; null where the period has no start. */
  start: number | null;
  /** Unix seconds; null where the period is open-ended. */
  end: number | null;
}

/** One informed entity of an alert, on one line. */
export interface Affected {
  /** GTFS parent stop_id (subway `A24`); null where the whole line is affected. */
  stopId: string | null;
  /** GTFS direction_id, 0 or 1; null for both directions. */
  directionId: number | null;
}

/** One alert as the endpoint returns it, for one line. */
export interface LineAlert {
  /** The MTA's alert id (`lmm:alert:274734:26`), also the GTFS-RT entity id MOTIS sees. */
  id: string;
  /** The MTA's own alert type (`Planned - Part Suspended`); null where the feed has none. */
  type: string | null;
  effect: Effect;
  cause: Cause;
  severity: Severity;
  /** When the alert applies; future periods are kept. */
  activePeriods: Period[];
  /** English plain text. */
  header: string;
  description: string | null;
  /** Where on this line: stops and directions. */
  affected: Affected[];
}

/** Every alert of both feeds, decoded once and shared by every request. */
export interface AlertIndex {
  /** Feed header timestamps, in Unix seconds. */
  updatedAt: { subway: number | null; bus: number | null };
  /** Line (GTFS route_id) to its alerts, in feed order. */
  lines: Record<string, LineAlert[]>;
}

interface Mapped {
  effect: Effect;
  cause: Cause;
  severity: Severity;
}

const types: Record<string, { effect: Effect; severity: Severity }> = table.types;

/** The MTA's alert type mapped to the standard fields, with the same table as the motis adapter. */
export function mapAlertType(type: string | null): Mapped & { known: boolean } {
  const planned = type?.startsWith(table.plannedPrefix) ?? false;
  const base = planned && type ? type.slice(table.plannedPrefix.length) : type;
  const entry = (type && Object.hasOwn(types, type) ? types[type] : undefined) ??
    (base && Object.hasOwn(types, base) ? types[base] : undefined);
  if (!entry) return { ...table.fallback, cause: "UNKNOWN_CAUSE", known: false };
  return { ...entry, cause: planned ? table.plannedCause : "UNKNOWN_CAUSE", known: true };
}

// The parts of the MTA's GTFS-RT JSON (`camsys%2F…-alerts.json`) read here.
interface FeedJson {
  header?: { timestamp?: number | string };
  entity?: {
    id: string;
    alert?: {
      active_period?: { start?: number | string; end?: number | string }[];
      informed_entity?: { route_id?: string; stop_id?: string; direction_id?: number }[];
      header_text?: Translated;
      description_text?: Translated;
      "transit_realtime.mercury_alert"?: { alert_type?: string };
    };
  }[];
}
interface Translated {
  translation?: { text?: string; language?: string }[];
}

function english(t: Translated | undefined): string | null {
  const all = t?.translation ?? [];
  const pick = all.find((x) => x.language === "en") ?? all.find((x) => !x.language);
  return pick?.text?.trim() || null;
}

function seconds(v: number | string | undefined): number | null {
  const n = Number(v);
  return v != null && Number.isFinite(n) && n > 0 ? n : null;
}

/** Decodes the MTA's subway and bus alert feeds (GTFS-RT JSON) into the per-line index. */
export function indexAlerts(
  subway: unknown,
  bus: unknown,
  onUnknownType: (type: string | null) => void = () => undefined,
): AlertIndex {
  const lines: Record<string, LineAlert[]> = {};
  for (const feed of [subway as FeedJson, bus as FeedJson]) {
    for (const entity of feed.entity ?? []) {
      const alert = entity.alert;
      if (!alert) continue;
      const type = alert["transit_realtime.mercury_alert"]?.alert_type || null;
      const { known, ...mapped } = mapAlertType(type);
      if (!known) onUnknownType(type);

      const byLine = new Map<string, Affected[]>();
      for (const ie of alert.informed_entity ?? []) {
        if (!ie.route_id) continue;
        const affected = byLine.get(ie.route_id) ?? [];
        affected.push({ stopId: ie.stop_id || null, directionId: ie.direction_id ?? null });
        byLine.set(ie.route_id, affected);
      }
      const base = {
        id: entity.id,
        type,
        ...mapped,
        activePeriods: (alert.active_period ?? []).map((p) => ({ start: seconds(p.start), end: seconds(p.end) })),
        header: english(alert.header_text) ?? "",
        description: english(alert.description_text),
      };
      for (const [line, affected] of byLine) {
        (lines[line] ??= []).push({ ...base, affected });
      }
    }
  }
  return {
    updatedAt: { subway: seconds((subway as FeedJson).header?.timestamp), bus: seconds((bus as FeedJson).header?.timestamp) },
    lines,
  };
}

export const MAX_LINES = 50;
const LINE_ID = /^[A-Za-z0-9+-]{1,16}$/;

/**
 * Parses `lines=A,C,M15+` from the raw query string. `+` is read literally, not as a space: Select Bus Service
 * routes end in it (`M15+`), and `%2B` works too.
 */
export function parseLines(search: string): string[] | { error: string } {
  const raw = search
    .replace(/^\?/, "")
    .split("&")
    .find((p) => p.startsWith("lines="))
    ?.slice("lines=".length);
  if (raw == null) return { error: "lines is required: lines=A,C,M15+" };
  let decoded: string;
  try {
    decoded = decodeURIComponent(raw);
  } catch {
    return { error: "lines is not valid percent-encoding" };
  }
  const ids = [...new Set(decoded.split(",").map((l) => l.trim()).filter(Boolean))];
  if (ids.length === 0) return { error: "lines must list at least one line" };
  if (ids.length > MAX_LINES) return { error: `lines may list at most ${MAX_LINES} lines` };
  if (!ids.every((id) => LINE_ID.test(id))) return { error: "lines holds an invalid line id" };
  return ids;
}

/** The alerts of the requested lines; a line without alerts answers an empty list. */
export function selectLines(index: AlertIndex, lines: string[]) {
  return {
    updatedAt: index.updatedAt,
    lines: Object.fromEntries(lines.map((l) => [l, Object.hasOwn(index.lines, l) ? index.lines[l] : []])),
  };
}
