// Bundle self-check: every preview card has the line-1 @dsCard marker, a
// title, the fonts link, and the inlined tokens. Run: node design-system/_shared/check.mjs
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = join(import.meta.dirname, '..');
const problems = [];
const cards = [];

function walk(dir) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) { if (name !== '_shared') walk(p); continue; }
    if (name.endsWith('.html')) cards.push(p);
  }
}
walk(root);

for (const p of cards) {
  const rel = relative(root, p).replace(/\\/g, '/');
  const src = readFileSync(p, 'utf8');
  const firstLine = src.slice(0, src.indexOf('\n')).trim();
  const m = firstLine.match(/^<!--\s*@dsCard\s+([^>]*?)-->$/);
  if (!m) { problems.push(`${rel}: line 1 is not an @dsCard marker`); continue; }
  for (const attr of ['group', 'name']) {
    if (!new RegExp(`${attr}="[^"]+"`).test(m[1])) problems.push(`${rel}: marker missing ${attr}=`);
  }
  if (!/<title>[^<]+<\/title>/.test(src)) problems.push(`${rel}: missing <title>`);
  if (!src.includes('fonts.googleapis.com/css2?family=Barlow+Condensed')) problems.push(`${rel}: missing fonts link`);
  if (!src.includes('--bg: #111318')) problems.push(`${rel}: tokens not inlined`);
  if (/<script\s+src=/.test(src)) problems.push(`${rel}: external script`);
  if (/<img\s/.test(src)) problems.push(`${rel}: <img> used (no images allowed)`);
}

console.log(`${cards.length} cards checked`);
if (problems.length) { console.log(problems.join('\n')); process.exit(1); }
console.log('all clean');
