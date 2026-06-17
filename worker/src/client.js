// Pure: project the registry's `client` gate to its public (wire) shape for the
// /v1/health response. Drops internal `_`-prefixed keys (e.g. `_doc`) so the
// registry can stay self-documenting without leaking notes onto the wire.
//
// Fail-open is the whole point: an ABSENT gate (a registry without `client`, an
// old worker, a fork, or the offline mock) returns null, and a client that
// receives null applies NO update gate. The gate is opt-in and inert until the
// author fills `minVersionCode`/`recommendedVersionCode` in league-profiles.json.
//
// Imported by both index.js (the health route) and the Node test harness, so the
// "what does the client see" rule never forks.
export function publicClient(client) {
  if (!client || typeof client !== 'object') return null;
  const out = {};
  for (const [k, v] of Object.entries(client)) {
    if (!k.startsWith('_')) out[k] = v;
  }
  return out;
}
