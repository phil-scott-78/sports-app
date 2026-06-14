// CLI-side loader for league-profiles.json. The pure resolver lives in
// resolve.mjs (no node builtins) so the Worker can reuse it; this file just adds
// fs-based loading and re-exports the resolver so existing imports keep working.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

export { resolve, leagueKeys } from './resolve.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
export const REGISTRY_PATH = join(HERE, '..', 'league-profiles.json');

export function loadRegistry(path = REGISTRY_PATH) {
  return JSON.parse(readFileSync(path, 'utf8'));
}

/** espnPath (e.g. "soccer/eng.1") from a league key. */
export function espnPath(key) {
  return key;
}
