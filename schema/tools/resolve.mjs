// Pure inheritance resolver for league-profiles.json — NO node builtins, so it
// bundles cleanly into the Cloudflare Worker (which can't import node:fs).
// profiles.mjs re-exports these and adds the fs-based loadRegistry for CLI use.

/** Find a node by key across leagues → profiles → families (in that order). */
function findNode(reg, key) {
  return reg.leagues?.[key] ?? reg.profiles?.[key] ?? reg.families?.[key] ?? null;
}

/**
 * Resolve a league/profile/family key to its effective config by walking the
 * `extends` chain (family → intermediate profile → league). Nearest wins;
 * scalars replace, objects shallow-merge.
 */
export function resolve(reg, key, seen = new Set()) {
  if (seen.has(key)) throw new Error(`cyclic extends at ${key}`);
  seen.add(key);
  const node = findNode(reg, key);
  if (!node) throw new Error(`unknown profile key: ${key}`);
  const base = node.extends ? resolve(reg, node.extends, seen) : {};
  const merged = { ...base };
  for (const [k, v] of Object.entries(node)) {
    if (k === 'extends') continue;
    merged[k] = v && typeof v === 'object' && !Array.isArray(v) && typeof base[k] === 'object'
      ? { ...base[k], ...v }
      : v;
  }
  merged._key = key;
  return merged;
}

/** All concrete league keys, optionally filtered. Skips dynamic `_*` buckets. */
export function leagueKeys(reg, { priority, sport, includeBuckets = false } = {}) {
  return Object.keys(reg.leagues)
    .filter(k => includeBuckets || !k.split('/')[1]?.startsWith('_'))
    .filter(k => !priority || reg.leagues[k].priority === priority)
    .filter(k => !sport || k.startsWith(sport + '/'));
}
