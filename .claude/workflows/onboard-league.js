export const meta = {
  name: 'onboard-league',
  description: 'Probe a new/changed sport or league, propose a normalized profile, adversarially verify it, and emit a ready-to-paste league-profiles.json entry',
  whenToUse: 'When a new league/sport appears (or an existing one changes rules/shape) and you want it dialed into the canonical schema without redoing the full research story. Pass args as a string (an ESPN "sport/league" slug, OR a free-text description of a novel sport) or {target, rules}.',
  phases: [
    { title: 'Probe', detail: 'run the deterministic probe against live data (or note no data source)' },
    { title: 'Propose', detail: 'classify vs existing families; draft profile + canonical mapping + edge cases' },
    { title: 'Verify', detail: 'adversarially re-fetch and try to break the proposal' },
    { title: 'Finalize', detail: 'merge fixes into a paste-ready registry entry + SCHEMA notes' },
  ],
}

const ROOT = 'B:/sports-app'
const FILES = `Repo files to read for context (absolute paths):
- ${ROOT}/schema/canonical.ts          (the wire contract + discriminators)
- ${ROOT}/schema/league-profiles.json  (families, intermediate profiles, league overrides + extends model)
- ${ROOT}/schema/SCHEMA.md             (mappings, period matrix, edge-case handling)
Deterministic tools you can run via Bash (cwd = ${ROOT}):
- node schema/tools/probe.mjs <sport>/<league> [--date YYYYMMDD] [--deep] [--raw]
- node schema/tools/verify.mjs <sport>/<league>`

// target may be a slug ("mma/ufb") or a free-text rules description. rules optional.
const target = typeof args === 'string' ? args : (args?.target ?? '')
const rules = (typeof args === 'object' && args?.rules) ? args.rules : ''
const looksLikeSlug = /^[a-z0-9-]+\/[a-z0-9._-]+$/i.test(target.trim())

const PROPOSAL_SCHEMA = {
  type: 'object',
  required: ['mode', 'family', 'discriminators', 'periodStructure', 'draftRegistryEntry', 'edgeCases', 'confidence'],
  properties: {
    mode: { type: 'string', description: 'existing-league-drift | new-league-existing-family | new-family | novel-sport-no-data' },
    family: { type: 'string', description: 'existing family key it fits, or proposed new family key' },
    espnPath: { type: ['string', 'null'] },
    espnLeagueId: { type: ['string', 'null'], description: 'verified live id as STRING, or null if no data source' },
    discriminators: { type: 'object', properties: {
      layout: { type: 'string' }, scoreKind: { type: 'string' }, competitorKind: { type: 'string' } } },
    periodStructure: { type: 'object', properties: {
      unit: { type: 'string' }, regulation: { type: 'number' }, lengthMin: { type: ['number', 'null'] }, otModel: { type: 'string' } } },
    canonicalMapping: { type: 'array', items: { type: 'object', properties: {
      canonicalField: { type: 'string' }, source: { type: 'string', description: 'raw json path / how derived' }, notes: { type: 'string' } } } },
    edgeCases: { type: 'array', items: { type: 'object', properties: {
      name: { type: 'string' }, espnShape: { type: 'string' }, handling: { type: 'string' } } } },
    needsNewContractTypes: { type: 'array', items: { type: 'string' }, description: 'new ScoreKind/PeriodUnit/Decision/Layout values canonical.ts would need (empty if it already fits)' },
    draftRegistryEntry: { type: 'string', description: 'JSON snippet to paste under leagues{} (and reference an existing or new family via extends)' },
    newFamilyEntry: { type: ['string', 'null'], description: 'JSON snippet for families{} if a new family is required, else null' },
    unverifiable: { type: 'array', items: { type: 'string' } },
    confidence: { type: 'string' },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['verdict', 'issues'],
  properties: {
    verdict: { type: 'string', description: 'solid | minor-fixes | major-fixes' },
    confirmed: { type: 'array', items: { type: 'string' }, description: 'claims re-verified against live data' },
    wrongPeriodStructure: { type: 'boolean' },
    wrongIds: { type: 'array', items: { type: 'string' } },
    missedEdgeCases: { type: 'array', items: { type: 'string' } },
    issues: { type: 'array', items: { type: 'object', properties: {
      severity: { type: 'string', description: 'critical|major|minor' },
      field: { type: 'string' }, problem: { type: 'string' }, fix: { type: 'string' }, evidenceUrl: { type: 'string' } } } },
  },
}

const FINAL_SCHEMA = {
  type: 'object',
  required: ['ready', 'registryEntry', 'schemaNotes'],
  properties: {
    ready: { type: 'boolean', description: 'true if safe to paste as-is; false if residual gaps need a human' },
    registryEntry: { type: 'string', description: 'FINAL JSON entry for leagues{} with verifier fixes applied' },
    newFamilyEntry: { type: ['string', 'null'] },
    contractChanges: { type: 'array', items: { type: 'string' }, description: 'exact canonical.ts edits if new discriminator values are needed' },
    schemaNotes: { type: 'string', description: 'markdown paragraph for SCHEMA.md documenting this league/family + its quirks' },
    residualGaps: { type: 'array', items: { type: 'string' } },
  },
}

phase('Probe')
const probeResult = await agent(
  `${FILES}\n\nTARGET: ${JSON.stringify(target)}\n${rules ? `RULES DESCRIPTION: ${rules}\n` : ''}` +
  (looksLikeSlug
    ? `This looks like an ESPN slug. Run \`node schema/tools/probe.mjs ${target} --deep\` via Bash. If eventCount is 0 (off-season), retry with a couple of plausible \`--date YYYYMMDD\` values for a date that likely had games, to capture live/final-state shape. Also run \`node schema/tools/verify.mjs ${target}\` if it already exists in the registry. Return: the full probe fingerprint JSON verbatim, plus a one-line classification (existing-and-clean / existing-with-drift / new-league / unreachable).`
    : `This is NOT an ESPN slug — it's a novel/proposed sport. There is no ESPN data to probe. Briefly try \`node schema/tools/probe.mjs <best-guess-slug>\` for any close existing ESPN sport that might serve as a structural analog, but expect failure. Return: a note that there is no live data source, plus any analog you found and what a sample payload would need to contain.`),
  { label: 'probe', phase: 'Probe', agentType: 'general-purpose' }
)

phase('Propose')
const proposal = await agent(
  `${FILES}\n\nYou are extending the canonical sports schema. Read canonical.ts and league-profiles.json FIRST to understand the discriminators (layout/scoreKind/competitorKind), the family→profile→league extends model, and what already exists.\n\nTARGET: ${JSON.stringify(target)}\n${rules ? `RULES: ${rules}\n` : ''}\nPROBE RESULT:\n${probeResult}\n\nYOUR JOB: propose how to dial this in with MINIMAL change.\n1. Decide mode: does it fit an existing family (just a new league override)? a new league in a family but with deltas? a brand-new family? or a novel sport with no data source?\n2. Reuse existing discriminators/period units if at all possible. Only set needsNewContractTypes if the contract genuinely cannot express it (e.g. a new scoreKind). Prefer composing existing pieces.\n3. Produce a draft league-profiles.json entry that uses \`extends\` to inherit everything shared, overriding ONLY the deltas. Include the VERIFIED espnLeagueId from the probe (as a string) when there is data.\n4. Map every canonical field to its raw source. List edge cases (weird rules!) and how each maps. Flag anything unverifiable.\nReturn the structured proposal.`,
  { label: 'propose', phase: 'Propose', schema: PROPOSAL_SCHEMA, agentType: 'general-purpose' }
)

phase('Verify')
const verdict = await agent(
  `${FILES}\n\nYou are an ADVERSARIAL verifier. A proposal was made to add/update a league in the canonical schema. Try to BREAK it.\n\nTARGET: ${JSON.stringify(target)}\nPROPOSAL:\n${JSON.stringify(proposal)}\n\n${looksLikeSlug
    ? `Independently re-fetch live data: \`node schema/tools/probe.mjs ${proposal.espnPath || target} --deep\` and, for any contested period/score/edge-case claim, also fetch the raw scoreboard/summary with WebFetch (https://site.api.espn.com/apis/site/v2/sports/${proposal.espnPath || target}/scoreboard and /summary?event=). Default to SKEPTICAL on: the league id (string, from live JSON only), the period structure (unit/count/length/OT), the scoreKind, and whether claimed edge cases match real data shape.`
    : `There is no live data. Critique the DESIGN instead: does the proposed model lose information? Does it actually need a new contract type or could it reuse an existing discriminator? Are the rule-driven edge cases fully covered? Is the extends inheritance correct and minimal?`}\nConfirm what is correct, and give concrete fixes with evidence for what is wrong. Return the structured verdict.`,
  { label: 'verify', phase: 'Verify', schema: VERDICT_SCHEMA, agentType: 'general-purpose' }
)

phase('Finalize')
const final = await agent(
  `${FILES}\n\nMerge the verifier's fixes into a FINAL, paste-ready result.\n\nPROPOSAL:\n${JSON.stringify(proposal)}\n\nVERDICT:\n${JSON.stringify(verdict)}\n\nApply every critical/major fix from the verdict to the registry entry. Produce: (1) the final league-profiles.json \`leagues{}\` entry (and a families{} entry if a new family is needed), with the extends chain correct and only true deltas overridden; (2) exact canonical.ts changes IF new discriminator values are required (else empty); (3) a SCHEMA.md markdown note documenting the league/family and its quirks; (4) residual gaps a human must resolve. Set ready=false if any critical issue is unresolved or the id/structure is unverified. Return the structured final.`,
  { label: 'finalize', phase: 'Finalize', schema: FINAL_SCHEMA, agentType: 'general-purpose' }
)

log(final.ready ? '✅ Draft ready to paste into schema/' : '⚠️ Draft has residual gaps — review before pasting')
return { target, probe: probeResult, proposal, verdict, final }
