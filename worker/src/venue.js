// venue.js — the Venue & Circuit "facts" tier (see canonical VenueFacts /
// CircuitFacts, and SCORES-APP-BUILD-SPEC §2.9). Pure map→map, no I/O, so it runs
// in Node tests + the Dart port alike. This is the RICH, lazy, on-tab-open detail
// for the Venue/Circuit tab — the cheap scoreboard already carried the header +
// join id (competitions[].venue.id / events[].circuit.id); these normalizers turn
// the one core fetch keyed by that id into the fact grid + photo/track-map.
//
// Two shapes, chosen by data presence (never sport name), exactly as the tab
// dispatches:
//   • stadium  → core venues/{id}  → normalizeVenueFacts
//   • F1 circuit → core circuits/{id} (+ resolved fastestLapDriver) → normalizeCircuitFacts
//
// EVIDENCE: every path below was OBSERVED in schema/espn-guide/core-venues-id.md
// and core-circuits-id.md. Fields NOT in the guide (stadium capacity/opened, wind)
// are omitted — never fabricated. See ledger #24–#25.

const https = (u) => (typeof u === 'string' ? u.replace(/^http:/, 'https:') : undefined);
const pick = (o, keys) =>
  Object.fromEntries(keys.filter((k) => o[k] != null).map((k) => [k, o[k]]));
const numOrU = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : undefined);

// ---- images / diagrams -------------------------------------------------------
// VERIFIED: images[]/diagrams[] carry {href, rel[], alt, width, height}. We keep
// only {href, rel} — the UI picks by rel token; alt is always "" and width/height
// are the fixed CDN dims (2000×1125), neither load-bearing.
function mapMedia(arr) {
  if (!Array.isArray(arr)) return undefined;
  const out = arr
    .filter((m) => m && typeof m.href === 'string')
    .map((m) => ({ href: https(m.href), rel: Array.isArray(m.rel) ? m.rel.filter((r) => typeof r === 'string') : [] }));
  return out.length ? out : undefined;
}

// Pick one href by an ordered preference of rel tokens; within a matching rel,
// prefer .svg (vector track maps) over .jpg. Returns undefined when nothing matches.
function pickByRel(media, order) {
  if (!Array.isArray(media) || !media.length) return undefined;
  for (const tok of order) {
    const hits = media.filter((m) => m.rel.includes(tok));
    if (!hits.length) continue;
    const svg = hits.find((m) => /\.svg(\?|$)/i.test(m.href));
    return (svg || hits[0]).href;
  }
  return media[0].href; // last resort: first available image
}

// ---- length / distance strings ----------------------------------------------
// VERIFIED (circuits): length/distance are STRINGS like "7.004 km" — split into a
// numeric value + unit, keep the original as `display`. QUIRK: NASCAR venues carry
// `length` as a NUMBER (miles) instead — handled in normalizeVenueFacts, not here.
function parseMeasure(s) {
  if (typeof s !== 'string' || !s.trim()) return undefined;
  const display = s.trim();
  const m = display.match(/^([\d.]+)\s*(.*)$/);
  const out = { display };
  if (m) {
    const value = parseFloat(m[1]);
    if (Number.isFinite(value)) out.value = value;
    const unit = (m[2] || '').trim();
    if (unit) out.unit = unit;
  }
  return out;
}

// ---- stadium venue facts (core venues/{id}) ---------------------------------
// grass → surface ('grass'|'turf'), indoor → roof ('open'|'indoor'). address
// (city 96% / state 62% / country 62%; address1 4% MMA-heavy). images 85%. NO
// capacity/opened — NOT OBSERVED on stadium venues (see ledger #24).
export function normalizeVenueFacts(raw) {
  if (!raw || typeof raw !== 'object' || raw.id == null) return null;
  const a = raw.address && typeof raw.address === 'object' ? raw.address : {};
  const images = mapMedia(raw.images);
  const out = {
    id: String(raw.id),
    name: raw.fullName || raw.shortName || '',
    ...pick({ city: a.city, state: a.state, country: a.country, address1: a.address1 },
      ['city', 'state', 'country', 'address1']),
  };
  if (images) {
    out.images = images;
    // preferred photo: an exterior day shot reads best, then any full, then interior.
    const photo = pickByRel(images, ['day', 'full', 'interior']);
    if (photo) out.photo = photo;
  }
  if (typeof raw.grass === 'boolean') out.surface = raw.grass ? 'grass' : 'turf';
  if (typeof raw.indoor === 'boolean') out.roof = raw.indoor ? 'indoor' : 'open';
  // Non-F1 racing (NASCAR ovals) degrade to venues/{id} length(mi, number)/turns —
  // the only track facts served outside the rich F1 circuits resource.
  const length = numOrU(raw.length);
  if (length != null) out.length = length;
  const turns = numOrU(raw.turns);
  if (turns != null) out.turns = turns;
  return out;
}

// ---- driver identity (resolved fastestLapDriver.$ref → athlete) -------------
function buildDriver(driver) {
  if (!driver || typeof driver !== 'object') return undefined;
  const name = driver.displayName || driver.fullName || driver.shortName;
  if (!name) return undefined;
  const out = { name: String(name) };
  const hs = https(driver.headshot?.href || driver.headshot);
  if (hs) out.headshot = hs;
  return out;
}

// ---- F1 circuit facts (core circuits/{id}) ----------------------------------
// The happy path: every fact 100% present for F1. `driver` is the pre-resolved
// fastestLapDriver athlete doc (the caller follows fastestLapDriver.$ref once,
// cached — the lap record barely changes). diagrams: prefer the dark track map.
export function normalizeCircuitFacts(raw, driver) {
  if (!raw || typeof raw !== 'object' || raw.id == null) return null;
  const a = raw.address && typeof raw.address === 'object' ? raw.address : {};
  const diagrams = mapMedia(raw.diagrams);
  const out = {
    id: String(raw.id),
    name: raw.fullName || '',
    ...pick({ city: a.city, country: a.country }, ['city', 'country']),
  };
  if (diagrams) {
    out.diagrams = diagrams;
    // track map: dark vector preferred, then light circuit, then day variants.
    const diagram = pickByRel(diagrams, ['circuit-dark', 'circuit', 'day-dark', 'day']);
    if (diagram) out.diagram = diagram;
  }
  if (typeof raw.direction === 'string' && raw.direction) out.direction = raw.direction;
  const established = numOrU(raw.established);
  if (established != null) out.established = established;
  const length = parseMeasure(raw.length);
  if (length) out.length = length;
  const distance = parseMeasure(raw.distance);
  if (distance) out.distance = distance;
  const laps = numOrU(raw.laps);
  if (laps != null) out.laps = laps;
  const turns = numOrU(raw.turns);
  if (turns != null) out.turns = turns;
  // lap record: time + year + (best-effort) driver identity.
  const lap = {};
  if (typeof raw.fastestLapTime === 'string' && raw.fastestLapTime) lap.time = raw.fastestLapTime;
  const year = numOrU(raw.fastestLapYear);
  if (year != null) lap.year = year;
  const drv = buildDriver(driver);
  if (drv) lap.driver = drv;
  if (Object.keys(lap).length) out.fastestLap = lap;
  return out;
}
