// verify.mjs — deterministic drift & gap detector for league-profiles.json.
// No LLM. Run anytime (locally, CI, cron) to catch: ESPN changing a league id,
// a slug going 404, a new status name appearing, a period structure that no
// longer matches reality, etc. This is the reusable "re-verify the models" tool.
//
// Usage:
//   node verify.mjs --priority v1          # check all v1 leagues
//   node verify.mjs --all                  # check every concrete league
//   node verify.mjs soccer/eng.1 nba       # check specific ones
//   node verify.mjs --all --json           # machine-readable report
//   node verify.mjs --all --snapshot       # write fingerprints to snapshots/
//   node verify.mjs --all --diff-snapshot  # compare live vs last snapshot (pure drift)
//
// Exit code: 0 = clean, 1 = at least one CRITICAL finding (fail CI on this).

import { writeFileSync, readFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadRegistry, resolve, leagueKeys } from './profiles.mjs';
import { probe } from './probe.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const SNAP_DIR = join(HERE, 'snapshots');

// Status names we already understand (don't flag these as "new/unmapped").
const KNOWN_STATUS = new Set([
  'STATUS_SCHEDULED', 'STATUS_IN_PROGRESS', 'STATUS_HALFTIME', 'STATUS_END_PERIOD',
  'STATUS_FIRST_HALF', 'STATUS_SECOND_HALF', 'STATUS_FINAL', 'STATUS_FULL_TIME',
  'STATUS_FINAL_AET', 'STATUS_FINAL_PEN', 'STATUS_RETIRED', 'STATUS_FINAL_OVERTIME',
  'STATUS_POSTPONED', 'STATUS_CANCELED', 'STATUS_CANCELLED', 'STATUS_SUSPENDED',
  'STATUS_ABANDONED', 'STATUS_FORFEIT', 'STATUS_RAIN_DELAY', 'STATUS_DELAYED',
  'STATUS_CUT', 'STATUS_FINISH', 'STATUS_CLASSIFIED', 'STATUS_END_OF_REGULATION',
  'STATUS_FIRST_INTERMISSION', 'STATUS_SECOND_INTERMISSION', 'STATUS_PERIOD_END',
]);

const C = { CRITICAL: 'CRITICAL', WARN: 'WARN', INFO: 'INFO' };

/** The checks. Each returns issues[]. Add a check = add a function here. */
const CHECKS = [
  function leagueReachable(cfg, fp, issues) {
    if (!fp.ok) issues.push({ sev: C.CRITICAL, field: 'endpoint',
      msg: `scoreboard unreachable (HTTP ${fp.httpStatus ?? '?'}: ${fp.error}) — slug renamed/removed?` });
  },
  function idMatches(cfg, fp, issues) {
    if (!fp.ok) return;
    const declared = cfg.espnLeagueId;
    if (declared == null) {
      issues.push({ sev: C.INFO, field: 'espnLeagueId', msg: `no declared id; live id is "${fp.league.id}"` });
    } else if (String(declared) !== String(fp.league.id)) {
      issues.push({ sev: C.CRITICAL, field: 'espnLeagueId',
        msg: `id drift: registry "${declared}" vs live "${fp.league.id}" (uid ${fp.league.uid})` });
    }
  },
  function scoreKindMatches(cfg, fp, issues) {
    if (!fp.ok || !fp.eventCount) return;
    const g = fp.observed.scoreKindGuess;
    if (g !== 'unknown' && g !== 'none' && cfg.scoreKind && g !== cfg.scoreKind) {
      issues.push({ sev: C.WARN, field: 'scoreKind',
        msg: `declared "${cfg.scoreKind}" but live looks "${g}" (samples: ${JSON.stringify(fp.observed.scoreSamples.slice(0, 4))})` });
    }
  },
  function layoutMatches(cfg, fp, issues) {
    if (!fp.ok || !fp.eventCount) return;
    if (cfg.layout && fp.observed.layoutGuess !== cfg.layout) {
      issues.push({ sev: C.WARN, field: 'layout',
        msg: `declared "${cfg.layout}" but observed ${fp.observed.competitorsPerComp[1]} competitors/comp → "${fp.observed.layoutGuess}"` });
    }
  },
  function lineScoresMatch(cfg, fp, issues) {
    if (!fp.ok || !fp.eventCount) return;
    if (cfg.hasLineScores === true && !fp.observed.hasLinescores && fp.observed.maxPeriod > 0)
      issues.push({ sev: C.INFO, field: 'hasLineScores', msg: 'declared true but none observed (may be off-season/pre-game only)' });
    if (cfg.hasLineScores === false && fp.observed.hasLinescores)
      issues.push({ sev: C.WARN, field: 'hasLineScores', msg: 'declared false but linescores ARE present live' });
  },
  function regulationPlausible(cfg, fp, issues) {
    if (!fp.ok) return;
    const obs = fp.observed.formatRegulation?.periods;
    if (obs != null && cfg.regulationPeriods != null && obs !== cfg.regulationPeriods) {
      const tennisCaveat = cfg.espnSport === 'tennis' || cfg._key?.startsWith('tennis/');
      issues.push({ sev: tennisCaveat ? C.INFO : C.WARN, field: 'regulationPeriods',
        msg: `registry ${cfg.regulationPeriods} vs live format.regulation.periods ${obs}${tennisCaveat ? ' (tennis: known-unreliable, expected)' : ''}` });
    }
  },
  function newStatusNames(cfg, fp, issues) {
    if (!fp.ok) return;
    const unknown = fp.observed.statusNames.filter(n => !KNOWN_STATUS.has(n));
    if (unknown.length)
      issues.push({ sev: C.WARN, field: 'status', msg: `unmapped status name(s): ${unknown.join(', ')} — add to canonical Phase mapping` });
  },
  function newSeasonTypes(cfg, fp, issues) {
    if (!fp.ok) return;
    const novel = fp.observed.seasonTypes.filter(t => ![1, 2, 3, 4, 6].includes(t));
    if (novel.length)
      issues.push({ sev: C.INFO, field: 'season.type', msg: `unseen season.type value(s): ${novel.join(', ')} (open enum)` });
  },
];

function diffSnapshot(prev, cur, issues) {
  if (!prev || !cur.ok) return;
  const watch = ['league.id', 'observed.layoutGuess', 'observed.scoreKindGuess', 'observed.hasLinescores', 'observed.multiCompetition'];
  const get = (o, p) => p.split('.').reduce((x, k) => x?.[k], o);
  for (const p of watch) {
    const a = get(prev, p), b = get(cur, p);
    if (a !== undefined && JSON.stringify(a) !== JSON.stringify(b))
      issues.push({ sev: p === 'league.id' ? C.CRITICAL : C.WARN, field: `Δ ${p}`, msg: `snapshot ${JSON.stringify(a)} → live ${JSON.stringify(b)}` });
  }
  const newStatus = (cur.observed.statusNames || []).filter(n => !(prev.observed.statusNames || []).includes(n));
  if (newStatus.length) issues.push({ sev: C.INFO, field: 'Δ status', msg: `new since snapshot: ${newStatus.join(', ')}` });
}

async function main() {
  const args = process.argv.slice(2);
  const flags = new Set(args.filter(a => a.startsWith('--')));
  // tokens that are VALUES for a flag (e.g. the "v1" after --priority), not league keys
  const valueIdx = new Set();
  args.forEach((a, i) => { if (a === '--priority') valueIdx.add(i + 1); });
  const explicit = args.filter((a, i) => !a.startsWith('--') && !valueIdx.has(i));
  const reg = loadRegistry();

  let keys;
  if (explicit.length) {
    // accept either full key (soccer/eng.1) or a short slug (nba) → resolve
    const all = leagueKeys(reg, {});
    keys = explicit.map(e => all.includes(e) ? e : all.find(k => k.endsWith('/' + e)) || e);
  } else if (flags.has('--all')) keys = leagueKeys(reg, {});
  else {
    const prio = ['v1', 'v2', 'v3'].find(p => flags.has('--' + p)) || (flags.has('--priority') ? args[args.indexOf('--priority') + 1] : 'v1');
    keys = leagueKeys(reg, { priority: prio });
  }

  const snapshot = flags.has('--snapshot');
  const diff = flags.has('--diff-snapshot');
  if (snapshot && !existsSync(SNAP_DIR)) mkdirSync(SNAP_DIR, { recursive: true });

  const results = [];
  // small concurrency to be polite to ESPN
  const pool = 6;
  for (let i = 0; i < keys.length; i += pool) {
    const batch = keys.slice(i, i + pool);
    const fps = await Promise.all(batch.map(async key => {
      const cfg = resolve(reg, key);
      const fp = await probe(key);
      const issues = [];
      for (const check of CHECKS) check(cfg, fp, issues);
      if (diff) {
        const snapFile = join(SNAP_DIR, key.replace(/\//g, '__') + '.json');
        if (existsSync(snapFile)) diffSnapshot(JSON.parse(readFileSync(snapFile, 'utf8')), fp, issues);
        else issues.push({ sev: C.INFO, field: 'snapshot', msg: 'no prior snapshot to diff' });
      }
      if (snapshot && fp.ok) writeFileSync(join(SNAP_DIR, key.replace(/\//g, '__') + '.json'), JSON.stringify(fp, null, 2));
      return { key, fp, issues };
    }));
    results.push(...fps);
  }

  const crit = results.flatMap(r => r.issues).filter(i => i.sev === C.CRITICAL).length;

  if (flags.has('--json')) {
    console.log(JSON.stringify({ checked: keys.length, critical: crit, results }, null, 2));
  } else {
    const ic = { CRITICAL: '✗', WARN: '!', INFO: 'i' };
    for (const { key, fp, issues } of results) {
      const tag = issues.some(i => i.sev === C.CRITICAL) ? '✗' : issues.length ? '!' : '✓';
      console.log(`${tag} ${key}${fp.ok ? ` (id ${fp.league.id}, ${fp.eventCount} events)` : ' [UNREACHABLE]'}`);
      for (const is of issues) console.log(`    ${ic[is.sev]} [${is.sev}] ${is.field}: ${is.msg}`);
    }
    const warn = results.flatMap(r => r.issues).filter(i => i.sev === C.WARN).length;
    console.log(`\n${results.length} leagues · ${crit} critical · ${warn} warnings`);
  }
  process.exit(crit ? 1 : 0);
}

main();
