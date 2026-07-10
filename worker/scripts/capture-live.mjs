// capture-live.mjs — snapshot a live game's PERISHABLE tiers until full time.
// The runnable half of the live-capture skill (.claude/skills/live-capture/):
// mid-match summaries, the core plays feed and the core situation/predictor
// cannot be recaptured after the game ends — start this when a notable game is
// on (or about to start) and let it run to the final whistle.
//
//   node scripts/capture-live.mjs <sport/league> [--event <id>] [--interval <s>] [--out <dir>]
//   npm run capture:live -- baseball/mlb
//   npm run capture:live -- basketball/wnba --event 401789123
//
// No --event → picks the first LIVE event on the league's scoreboard, else the
// next scheduled one and waits for kickoff. Snapshots land in
// mock/live-capture/<league>__<event>/ (gitignored) as timestamped files:
//   snap_summary_<HHMMSS>.json        site summary (every cycle)
//   snap_scoreboard_<HHMMSS>.json     league scoreboard (every cycle)
//   snap_coreplays_<HHMMSS>.json      core plays, ALL pages merged (every cycle)
//   snap_situation_<HHMMSS>.json      core situation+predictor (live only; 404s skipped)
//   snap_*_final_<HHMMSS>.json        one last pass after state → post
// Byte-identical payloads are NOT re-written (pregame and halftime cycles repeat
// verbatim for an hour+ — only the snapshots where something moved land on disk;
// final passes always write). Exit condition is scoreboard STATE (never play-text
// heuristics — "End Regular Time" fires at 90' even when extra time follows).
//
// NOTE on the predictor: for basketball it is a STATIC pregame model (VERIFIED
// live 2026-07-09, WNBA 401857051: lastModified/teamPredWinpct never moved all
// game) — the LIVE win probability rides the summary's winprobability[] and the
// scoreboard's situation.lastPlay.probability, both captured every cycle. Other
// sports' predictors are unverified, so we still fetch it each pass (the dedupe
// makes the repeats free); don't expect a predictor timeline out of basketball.
//
// Afterwards: turn snapshots into committed fixtures per the skill §3 (the
// trim/slim functions in capture-fixtures.mjs / capture-extra.mjs are part of
// the contract chain), or run `npm run capture-extra -- --only situation
// matchfeeds` DURING the game for the committed sections directly.

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));

const args = process.argv.slice(2);
const key = args.find((a) => !a.startsWith('--'));
if (!key || !key.includes('/')) {
  console.error('usage: node scripts/capture-live.mjs <sport/league> [--event <id>] [--interval <s>] [--out <dir>]');
  process.exit(1);
}
const flag = (name, dflt) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : dflt;
};
const wantEvent = flag('event', null);
const intervalS = Math.max(30, Number(flag('interval', 120)));
const MAX_CYCLES = 200; // hard stop ≈ 6h40m at the default cadence

const site = `https://site.api.espn.com/apis/site/v2/sports/${key}`;
const core = `https://sports.core.api.espn.com/v2/sports/${key.replace('/', '/leagues/')}`;

const j = async (u) => {
  const r = await fetch(u);
  if (!r.ok) throw new Error(`HTTP ${r.status} ${u}`);
  return r.json();
};
const ts = () => new Date().toISOString().slice(11, 19).replace(/:/g, '');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- pick the event ----------------------------------------------------------
const sb0 = await j(`${site}/scoreboard`);
const events = sb0.events || [];
const stateOf = (e) => e.competitions?.[0]?.status?.type?.state ?? '?';
let ev = wantEvent
  ? events.find((e) => String(e.id) === String(wantEvent))
  : events.find((e) => stateOf(e) === 'in')
    ?? events
      .filter((e) => stateOf(e) === 'pre')
      .sort((a, b) => Date.parse(a.date) - Date.parse(b.date))[0];
if (!ev) {
  console.error(`no ${wantEvent ? `event ${wantEvent}` : 'live or upcoming event'} on the ${key} scoreboard`);
  process.exit(1);
}
const eventId = String(ev.id);
const compId = String(ev.competitions?.[0]?.id ?? eventId);
const outDir = flag('out', join(HERE, '..', 'mock', 'live-capture', `${key.replace('/', '__')}__${eventId}`));
mkdirSync(outDir, { recursive: true });
console.log(`● ${ev.shortName} (${eventId}, ${stateOf(ev)}) → ${outDir}`);
console.log(`  every ${intervalS}s until state=post\n`);

// Dedupe by resource kind: skip the write when the payload is byte-identical to
// the last one written (pregame/halftime cycles repeat verbatim). Final passes
// force-write — the settled payloads are what the fixture step (skill §3) prefers.
const lastBody = new Map();
const save = (kind, tag, data, { force = false } = {}) => {
  const body = JSON.stringify(data);
  if (!force && lastBody.get(kind) === body) return false;
  lastBody.set(kind, body);
  writeFileSync(join(outDir, `snap_${kind}_${tag}.json`), body);
  return true;
};

// ---- one capture pass ----------------------------------------------------------
async function fullPlays() {
  const first = await j(`${core}/events/${eventId}/competitions/${compId}/plays?limit=300`);
  const items = [...(first.items || [])];
  for (let p = 2; p <= (first.pageCount || 1); p++) {
    const page = await j(`${core}/events/${eventId}/competitions/${compId}/plays?limit=300&page=${p}`).catch(() => null);
    if (page?.items) items.push(...page.items);
  }
  return { count: first.count ?? items.length, items };
}

async function pass(suffix = '') {
  const t = ts();
  const tag = suffix ? `${suffix}_${t}` : t;
  const force = suffix === 'final';
  let state = '?', detail = '', wrote = 0;
  try {
    const sb = await j(`${site}/scoreboard`);
    if (save('scoreboard', tag, sb, { force })) wrote++;
    const e = (sb.events || []).find((x) => String(x.id) === eventId);
    state = e ? stateOf(e) : 'gone';
    detail = e?.competitions?.[0]?.status?.type?.shortDetail ?? '';
  } catch (err) { console.log(`  ${t} scoreboard: ${err.message}`); }
  try {
    if (save('summary', tag, await j(`${site}/summary?event=${eventId}`), { force })) wrote++;
  } catch (err) { console.log(`  ${t} summary: ${err.message}`); }
  let playCount = '—';
  try {
    const plays = await fullPlays();
    if (plays.items.length) { if (save('coreplays', tag, plays, { force })) wrote++; playCount = plays.count; }
  } catch { /* some sports have no plays feed */ }
  if (state === 'in') {
    // live-only core resources — the whole reason this script exists
    try {
      const situation = await j(`${core}/events/${eventId}/competitions/${compId}/situation`).catch(() => null);
      const predictor = await j(`${core}/events/${eventId}/competitions/${compId}/predictor`).catch(() => null);
      if (situation || predictor) { if (save('situation', tag, { situation, predictor }, { force })) wrote++; }
    } catch { /* 404 between states — fine */ }
  }
  console.log(`  ${t} state=${state} ${detail} plays=${playCount}${wrote ? '' : ' (unchanged — nothing written)'}`);
  return state;
}

// ---- the loop -------------------------------------------------------------------
for (let i = 0; i < MAX_CYCLES; i++) {
  const state = await pass();
  if (state === 'post') {
    console.log('\nfinal reached — two safety passes for the settled payloads');
    await sleep(90_000);
    await pass('final');
    await sleep(120_000);
    await pass('final');
    break;
  }
  if (state === 'gone') { console.log('event left the scoreboard — stopping'); break; }
  await sleep(intervalS * 1000);
}
console.log(`\ndone → ${outDir}`);
console.log('next: fixtures/goldens per .claude/skills/live-capture/ §3');
