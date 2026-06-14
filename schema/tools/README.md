# Schema verification & onboarding toolkit

A reusable system for keeping the canonical schema honest as the world changes —
ESPN tweaks a field, a league changes its id, or someone launches Ultimate
Fighting Baseball with rules nobody's seen. The expensive part of building the
schema was the *methodology* (fetch live → compare to assumptions → adversarially
find gaps); this packages that methodology so re-verifying or onboarding is a
one-liner.

**Two halves, by design:**

| | Tool | LLM? | When |
|---|---|---|---|
| **Verify existing** | `verify.mjs` (uses `probe.mjs`) | No — pure code | Anytime / CI / cron. Catches drift & gaps for free. |
| **Onboard new/weird** | `onboard-league` workflow | Yes — only when there's judgment | A new league/sport, or rules that don't fit. |

The deterministic half runs forever at zero cost. The LLM half only fires when
there's actual design work (classify a new sport, propose a profile).

---

## 1. `probe.mjs` — fingerprint a live endpoint

The single source of truth for "what does this endpoint *actually* look like
right now." Pure stdlib + Node's built-in `fetch`.

```bash
node probe.mjs soccer/eng.1                 # structural fingerprint
node probe.mjs basketball/nba --date 20250622   # capture a known game day (off-season)
node probe.mjs golf/pga --deep              # also probe summary of the first event
node probe.mjs racing/f1 --raw > raw.json   # dump raw scoreboard JSON
```

Emits JSON: league id/uid/abbr, event count, and `observed.*` — competitor
cardinality, layout/scoreKind guesses, status names/states seen, max period,
`format.regulation`, whether linescores/homeAway/curatedRank/hadPlayoff/shootout
appear. Everything `verify`/`onboard` reason about flows from here.

## 2. `verify.mjs` — drift & gap detector (the reusable re-verify)

Loads `league-profiles.json`, resolves each league's effective config (the
`extends` chain), probes it live, and diffs declared vs reality.

```bash
node verify.mjs --priority v1          # check all v1 leagues (default)
node verify.mjs --all                  # every concrete league
node verify.mjs soccer/eng.1 nba       # specific (full key or short slug)
node verify.mjs --all --json           # machine-readable
node verify.mjs --all --snapshot       # record fingerprints to snapshots/
node verify.mjs --all --diff-snapshot  # compare live vs last snapshot (pure drift)
```

**Findings & severity:**
- `CRITICAL` — id drift (registry vs live mismatch), slug unreachable (renamed/
  removed). **Exit code 1** → fail CI on these.
- `WARN` — scoreKind/layout/lineScores/regulation mismatch, an **unmapped status
  name** appearing live (add it to the `Phase` mapping).
- `INFO` — no declared id, new `season.type` value (open enum), etc.

**Two modes of catching change:**
1. *Against the registry* — does live still match what we declared?
2. *Against a snapshot* (`--snapshot` then later `--diff-snapshot`) — what changed
   since last week, even in fields the registry doesn't pin? This catches ESPN
   silently restructuring before it bites you.

**Add a check** = add one function to the `CHECKS` array in `verify.mjs`.
**Teach it a status name** = add to `KNOWN_STATUS`.

### Cron/CI recipe
Run weekly (or in CI) and alert on non-zero exit:
```bash
node schema/tools/verify.mjs --all || echo "schema drift detected — see output"
```
Or wire it to a scheduled Claude routine (`/schedule`) that runs verify and, on
any CRITICAL, kicks off `onboard-league` for the affected slug.

## 3. `onboard-league` workflow — dial in something new

For when there's judgment to do. Probes → classifies against existing families →
proposes a minimal profile (reusing discriminators, overriding only deltas) →
**adversarially verifies** it against live data → emits a paste-ready
`league-profiles.json` entry + any `canonical.ts` changes + a `SCHEMA.md` note.

```js
// an existing/changed ESPN league:
Workflow({ name: 'onboard-league', args: 'basketball/nbl' })

// a brand-new ESPN sport that may need a NEW family:
Workflow({ name: 'onboard-league', args: 'lacrosse/pll' })

// a novel sport with NO data source — design from rules (your UFB case):
Workflow({ name: 'onboard-league', args: {
  target: 'Ultimate Fighting Baseball',
  rules: '9 innings; a tied inning triggers a 1-round MMA bout between pitchers; '
       + 'a KO is worth 2 runs; game can end by knockout (sudden death)...' } })
```

It auto-detects mode (slug vs description). For a real slug it fetches and
verifies; for a novel sport it designs from the rules and flags what can't be
verified without a data feed. Output includes `ready: true/false` — false means
residual gaps need a human before pasting.

The workflow **reuses the deterministic tools** (its agents run `probe.mjs`/
`verify.mjs` via Bash), so live-data claims are grounded, not guessed.

## 4. `profiles.mjs` — shared resolver

`loadRegistry()`, `resolve(reg, key)` (walks the `extends` chain),
`leagueKeys(reg, {priority, sport})`. One place for the inheritance logic —
imported by the tools here and intended for reuse by the Cloudflare Worker so the
"resolve a league's config" rule never forks.

---

## Typical flows

**Routine health check:** `node verify.mjs --all` → fix any CRITICAL (usually an
id that ESPN moved) → commit.

**ESPN changed something subtle:** keep `--snapshot` files in git; `--diff-snapshot`
in CI shows exactly what shifted.

**New league/sport/weird-rules:** run `onboard-league` → review the draft (esp.
`residualGaps`) → paste `registryEntry` into `league-profiles.json`, apply any
`contractChanges` to `canonical.ts`, add the `schemaNotes` to `SCHEMA.md` → run
`node verify.mjs <newslug>` to confirm it now checks clean.
