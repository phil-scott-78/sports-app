# Authoring conventions — Broadcast Dark design-system preview cards

Every file in this bundle is a **self-contained preview card** rendered standalone
by the Claude Design "Design System" pane. Follow these rules exactly.

## File skeleton

Line 1 must be EXACTLY this comment (the pane indexes cards from it):

    <!-- @dsCard group="<Group>" name="<Card name>" subtitle="<Variants shown>" -->

Groups used in this bundle: `Foundations`, `Components`, `Situation cards`,
`Event feeds`, `Screens`.

Then:

```html
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Card name</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@500;600;700&family=Archivo:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
/* 1. Paste the ENTIRE contents of _shared/tokens.css here, verbatim. */
/* 2. Card-local CSS below it. */
</style>
</head>
<body>
  <!-- specimens -->
</body>
</html>
```

No JavaScript unless a card genuinely needs it (prefer none). No external
assets beyond the Google Fonts link. No images — diagrams are inline SVG or
CSS shapes (the system has no logos, no photos; photo areas are `--track`
media-well placeholders).

## Layout of a card page

- `body` padding 24px, background `--bg`.
- Content in a single column, `max-width: 428px` (the system's phone width;
  CSS px map 1:1 to Flutter logical px).
- **Component cards**: stack each specimen/variant vertically with 28px gaps;
  above each specimen a `caption-faint`-style annotation line naming the
  variant and the key specs (e.g. `HERO CARD — LIVE BODY · r20 · pad 16×18`).
  Annotations are the only non-diegetic text; keep them faint so the specimen
  reads first.
- **Screen cards**: render the full screen in a 428px frame (`border: 1px
  solid var(--divider); border-radius: 24px; overflow: hidden`), no
  annotations inside the frame.

## Non-negotiable system rules (from app/DESIGN.md — read the relevant §§ first)

- Dark only. Neutral chrome; team identity enters ONLY as data-driven color on
  shapes (bars, dots, pips, fills) — never a logo, never colored text (single
  exception: §10 comparison-card header legends).
- Numbers that can change live = Barlow Condensed 600/700 + tabular figures.
  Words = Archivo. UPPERCASE only in the 10–12px letterspaced label tier and
  Barlow display text.
- Winner/leader = `--text` at 600–700; trailer = `--text-dim` regular. That
  asymmetry, not color, is how results read.
- One inverted (light) card per screen, maximum. Everything else quiet.
- Dashed = not yet. The cut line = 2px dashed `--live` + centered label.
- Copy voice: terse middot fragments (`Suzuki up · 2–1 · 2 out`), en-dash
  scores (2–1), soccer prime minutes (73′), no emoji (★ is the one glyph),
  no exclamation points. Sports vernacular, no explanation.
- Use realistic, plausible fake data (real-looking team/player names are fine).
- No shadows on resting cards. Separation = surface contrast.

## Fidelity source

`app/DESIGN.md` is the spec — match its px/weight/color values exactly (they
are all in §§2–10). `design-mirror/*.dc.html` are the original mockups; consult
them for CSS detail when the spec is ambiguous, but the spec wins on conflict.
