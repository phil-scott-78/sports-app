# ESPN API — observed data guide

> A definitive, evidence-based guide to what ESPN's unofficial API actually serves, built by crawling real responses from the past year across every sport in `schema/league-profiles.json` (crawler: `schema/tools/crawl.mjs`, corpus: `schema/crawl-data/`, this rollup: `schema/tools/rollup.mjs`). The **site/summary API** is crawled by fixed URL templates (endpoint families per https://github.com/pseudo-r/Public-ESPN-API); the **core API** (`sports.core.api.espn.com`) is a hypermedia graph, so it is *discovered* by following every `$ref` from each league root and its events — reaching resources whose URLs can't be guessed (e.g. tennis competitions, where the competition id differs from the event id). Everything below was OBSERVED live; nothing is from documentation. Regenerate: crawl, then roll up.

Corpus: 2864 successful responses, 34 leagues, 17 sports. Crawled 2026-07-08 → 2026-07-08.

## Start here: per-sport guides

**If you're building for one sport, read its [per-sport guide](./by-sport/index.md) first** — it names the leagues + their competition shape, the endpoints that work (and the ones that 404), the reachable core-graph resources, and the fields unique to that sport, in one page. The tables below are the exhaustive cross-sport reference behind those guides.

- [`australian-football`](./by-sport/australian-football.md)
- [`baseball`](./by-sport/baseball.md)
- [`basketball`](./by-sport/basketball.md)
- [`cricket`](./by-sport/cricket.md)
- [`field-hockey`](./by-sport/field-hockey.md)
- [`football`](./by-sport/football.md)
- [`golf`](./by-sport/golf.md)
- [`hockey`](./by-sport/hockey.md)
- [`lacrosse`](./by-sport/lacrosse.md)
- [`mma`](./by-sport/mma.md)
- [`racing`](./by-sport/racing.md)
- [`rugby`](./by-sport/rugby.md)
- [`rugby-league`](./by-sport/rugby-league.md)
- [`soccer`](./by-sport/soccer.md)
- [`tennis`](./by-sport/tennis.md)
- [`volleyball`](./by-sport/volleyball.md)
- [`water-polo`](./by-sport/water-polo.md)

## Per-endpoint field guides

**Site / summary API** (flat, fixed URL templates):

- [`golf-playersummary`](./golf-playersummary.md) — 2 responses, 1 sports
- [`injuries`](./injuries.md) — 23 responses, 11 sports
- [`news`](./news.md) — 34 responses, 17 sports
- [`rankings`](./rankings.md) — 5 responses, 4 sports
- [`scoreboard`](./scoreboard.md) — 475 responses, 17 sports
- [`standings`](./standings.md) — 68 responses, 17 sports
- [`summary`](./summary.md) — 95 responses, 13 sports
- [`team-roster`](./team-roster.md) — 46 responses, 11 sports
- [`team-schedule`](./team-schedule.md) — 20 responses, 9 sports
- [`team-stats`](./team-stats.md) — 13 responses, 5 sports
- [`teams`](./teams.md) — 33 responses, 16 sports

**Core API resource graph** (205 distinct resource shapes, discovered by following `$ref` links from each league root + its events — see `crawlGraph` in `crawl.mjs`):

- [`core-calendar`](./core-calendar.md) — 33 responses, 16 sports
- [`core-competition`](./core-competition.md) — 33 responses, 16 sports
- [`core-competition-status`](./core-competition-status.md) — 33 responses, 16 sports
- [`core-competitor`](./core-competitor.md) — 33 responses, 16 sports
- [`core-event`](./core-event.md) — 33 responses, 16 sports
- [`core-events`](./core-events.md) — 33 responses, 16 sports
- [`core-league`](./core-league.md) — 33 responses, 16 sports
- [`core-season`](./core-season.md) — 33 responses, 16 sports
- [`core-season-type`](./core-season-type.md) — 33 responses, 16 sports
- [`core-season-types`](./core-season-types.md) — 33 responses, 16 sports
- [`core-seasons`](./core-seasons.md) — 33 responses, 16 sports
- [`core-calendar-blacklist`](./core-calendar-blacklist.md) — 32 responses, 15 sports
- [`core-calendar-offdays`](./core-calendar-offdays.md) — 32 responses, 15 sports
- [`core-calendar-ondays`](./core-calendar-ondays.md) — 32 responses, 15 sports
- [`core-calendar-whitelist`](./core-calendar-whitelist.md) — 32 responses, 15 sports
- [`core-competition-broadcasts`](./core-competition-broadcasts.md) — 31 responses, 15 sports
- [`core-competitor-linescores`](./core-competitor-linescores.md) — 27 responses, 14 sports
- [`core-competitor-score`](./core-competitor-score.md) — 27 responses, 13 sports
- [`core-competitor-scores-id`](./core-competitor-scores-id.md) — 27 responses, 13 sports
- [`core-media-id`](./core-media-id.md) — 27 responses, 13 sports
- [`core-competitor-linescores-id-id`](./core-competitor-linescores-id-id.md) — 24 responses, 12 sports
- [`core-rankings`](./core-rankings.md) — 26 responses, 12 sports
- [`core-season-teams`](./core-season-teams.md) — 25 responses, 12 sports
- [`core-season-teams-id`](./core-season-teams-id.md) — 25 responses, 12 sports
- [`core-season-types-id-teams-id-record`](./core-season-types-id-teams-id-record.md) — 24 responses, 12 sports
- [`core-season-types-id-teams-id-records-id`](./core-season-types-id-teams-id-records-id.md) — 20 responses, 12 sports
- [`core-venues-id`](./core-venues-id.md) — 26 responses, 12 sports
- [`core-competitor-statistics-id`](./core-competitor-statistics-id.md) — 21 responses, 11 sports
- [`core-season-athletes-id-eventlog`](./core-season-athletes-id-eventlog.md) — 23 responses, 11 sports
- [`core-season-teams-id-events`](./core-season-teams-id-events.md) — 22 responses, 11 sports
- [`core-season-types-id-groups`](./core-season-types-id-groups.md) — 23 responses, 11 sports
- [`core-season-types-id-groups-id`](./core-season-types-id-groups-id.md) — 23 responses, 11 sports
- [`core-competitor-statistics`](./core-competitor-statistics.md) — 20 responses, 10 sports
- [`core-notes`](./core-notes.md) — 22 responses, 10 sports
- [`core-season-athletes-id`](./core-season-athletes-id.md) — 21 responses, 10 sports
- [`core-season-rankings`](./core-season-rankings.md) — 17 responses, 10 sports
- [`core-season-types-id-athletes-id-statistics-id`](./core-season-types-id-athletes-id-statistics-id.md) — 14 responses, 10 sports
- [`core-season-types-id-groups-id-children`](./core-season-types-id-groups-id-children.md) — 20 responses, 10 sports
- [`core-competition-plays-id`](./core-competition-plays-id.md) — 17 responses, 9 sports
- [`core-competition-relevancy`](./core-competition-relevancy.md) — 20 responses, 9 sports
- [`core-competitor-roster`](./core-competitor-roster.md) — 19 responses, 9 sports
- [`core-plays`](./core-plays.md) — 18 responses, 9 sports
- [`core-season-teams-id-athletes`](./core-season-teams-id-athletes.md) — 17 responses, 9 sports
- [`core-season-types-id-athletes-id-statistics`](./core-season-types-id-athletes-id-statistics.md) — 13 responses, 9 sports
- [`core-situation`](./core-situation.md) — 19 responses, 9 sports
- [`core-competitor-leaders`](./core-competitor-leaders.md) — 17 responses, 8 sports
- [`core-competitor-records`](./core-competitor-records.md) — 13 responses, 8 sports
- [`core-competitor-records-id`](./core-competitor-records-id.md) — 13 responses, 8 sports
- [`core-competitor-roster-id-statistics-id`](./core-competitor-roster-id-statistics-id.md) — 16 responses, 8 sports
- [`core-franchises`](./core-franchises.md) — 19 responses, 8 sports
- [`core-franchises-id`](./core-franchises-id.md) — 19 responses, 8 sports
- [`core-league-athletes`](./core-league-athletes.md) — 12 responses, 8 sports
- [`core-odds`](./core-odds.md) — 18 responses, 8 sports
- [`core-positions-id`](./core-positions-id.md) — 17 responses, 8 sports
- [`core-season-athletes-id-notes`](./core-season-athletes-id-notes.md) — 17 responses, 8 sports
- [`core-season-types-id-teams-id-athletes-id-statistics-id`](./core-season-types-id-teams-id-athletes-id-statistics-id.md) — 16 responses, 8 sports
- [`core-season-types-id-teams-id-leaders`](./core-season-types-id-teams-id-leaders.md) — 16 responses, 8 sports
- [`core-teams-id-notes`](./core-teams-id-notes.md) — 19 responses, 8 sports
- [`core-athletes-id`](./core-athletes-id.md) — 9 responses, 7 sports
- [`core-season-athletes`](./core-season-athletes.md) — 18 responses, 7 sports
- [`core-season-types-id-groups-id-standings`](./core-season-types-id-groups-id-standings.md) — 11 responses, 7 sports
- [`core-season-types-id-groups-id-standings-id`](./core-season-types-id-groups-id-standings-id.md) — 11 responses, 7 sports
- [`core-season-types-id-weeks`](./core-season-types-id-weeks.md) — 11 responses, 7 sports
- [`core-transactions`](./core-transactions.md) — 13 responses, 7 sports
- [`core-athletes-id-contracts`](./core-athletes-id-contracts.md) — 7 responses, 6 sports
- [`core-season-types-id-groups-id-teams`](./core-season-types-id-groups-id-teams.md) — 11 responses, 6 sports
- [`core-season-types-id-teams-id-statistics`](./core-season-types-id-teams-id-statistics.md) — 14 responses, 6 sports
- [`core-season-types-id-teams-id-statistics-id`](./core-season-types-id-teams-id-statistics-id.md) — 14 responses, 6 sports
- [`core-season-types-id-weeks-id`](./core-season-types-id-weeks-id.md) — 9 responses, 6 sports
- [`core-season-types-id-weeks-id-rankings`](./core-season-types-id-weeks-id-rankings.md) — 9 responses, 6 sports
- [`core-teams-id-injuries`](./core-teams-id-injuries.md) — 15 responses, 6 sports
- [`core-athlete`](./core-athlete.md) — 8 responses, 5 sports
- [`core-athletes-id-statistics-id`](./core-athletes-id-statistics-id.md) — 7 responses, 5 sports
- [`core-coaches-id`](./core-coaches-id.md) — 8 responses, 5 sports
- [`core-competition-officials`](./core-competition-officials.md) — 13 responses, 5 sports
- [`core-competition-officials-id`](./core-competition-officials-id.md) — 8 responses, 5 sports
- [`core-season-teams-id-ranks`](./core-season-teams-id-ranks.md) — 9 responses, 5 sports
- [`core-season-types-id-groups-id-teams-id-records-id`](./core-season-types-id-groups-id-teams-id-records-id.md) — 7 responses, 5 sports
- [`core-season-types-id-weeks-id-rankings-id`](./core-season-types-id-weeks-id-rankings-id.md) — 7 responses, 5 sports
- [`core-athletes-id-statistics`](./core-athletes-id-statistics.md) — 5 responses, 4 sports
- [`core-athletes-id-statisticslog`](./core-athletes-id-statisticslog.md) — 7 responses, 4 sports
- [`core-casinos-id`](./core-casinos-id.md) — 11 responses, 4 sports
- [`core-competition-leaders`](./core-competition-leaders.md) — 4 responses, 4 sports
- [`core-competition-odds-id`](./core-competition-odds-id.md) — 12 responses, 4 sports
- [`core-competition-odds-id-propBets`](./core-competition-odds-id-propBets.md) — 11 responses, 4 sports
- [`core-providers-id`](./core-providers-id.md) — 12 responses, 4 sports
- [`core-season-athletes-id-injuries-id`](./core-season-athletes-id-injuries-id.md) — 5 responses, 4 sports
- [`core-season-awards-id`](./core-season-awards-id.md) — 7 responses, 4 sports
- [`core-season-coaches`](./core-season-coaches.md) — 4 responses, 4 sports
- [`core-season-coaches-id`](./core-season-coaches-id.md) — 6 responses, 4 sports
- [`core-season-futures`](./core-season-futures.md) — 7 responses, 4 sports
- [`core-season-futures-id`](./core-season-futures-id.md) — 7 responses, 4 sports
- [`core-season-teams-id-awards`](./core-season-teams-id-awards.md) — 7 responses, 4 sports
- [`core-season-teams-id-coaches`](./core-season-teams-id-coaches.md) — 5 responses, 4 sports
- [`core-season-types-id-corrections`](./core-season-types-id-corrections.md) — 4 responses, 4 sports
- [`core-season-types-id-leaders`](./core-season-types-id-leaders.md) — 7 responses, 4 sports
- [`core-tournaments-id-seasons-id`](./core-tournaments-id-seasons-id.md) — 7 responses, 4 sports
- [`core-athletes-id-seasons`](./core-athletes-id-seasons.md) — 6 responses, 3 sports
- [`core-awards`](./core-awards.md) — 6 responses, 3 sports
- [`core-awards-id`](./core-awards-id.md) — 6 responses, 3 sports
- [`core-coaches-id-record-id`](./core-coaches-id-record-id.md) — 4 responses, 3 sports
- [`core-competition-powerindex`](./core-competition-powerindex.md) — 5 responses, 3 sports
- [`core-competition-probabilities-id`](./core-competition-probabilities-id.md) — 5 responses, 3 sports
- [`core-competitor-roster-id-projections`](./core-competitor-roster-id-projections.md) — 3 responses, 3 sports
- [`core-leaders`](./core-leaders.md) — 3 responses, 3 sports
- [`core-leaders-id`](./core-leaders-id.md) — 3 responses, 3 sports
- [`core-powerindex`](./core-powerindex.md) — 5 responses, 3 sports
- [`core-predictor`](./core-predictor.md) — 5 responses, 3 sports
- [`core-probabilities`](./core-probabilities.md) — 5 responses, 3 sports
- [`core-season-awards`](./core-season-awards.md) — 6 responses, 3 sports
- [`core-season-freeagents`](./core-season-freeagents.md) — 3 responses, 3 sports
- [`core-season-rankings-id`](./core-season-rankings-id.md) — 4 responses, 3 sports
- [`core-season-teams-id-transactions`](./core-season-teams-id-transactions.md) — 3 responses, 3 sports
- [`core-season-types-id-coaches-id-record`](./core-season-types-id-coaches-id-record.md) — 4 responses, 3 sports
- [`core-season-types-id-teams-id-athletes-id-statistics`](./core-season-types-id-teams-id-athletes-id-statistics.md) — 3 responses, 3 sports
- [`core-season-types-id-weeks-id-teams-id-ranks-id`](./core-season-types-id-weeks-id-teams-id-ranks-id.md) — 4 responses, 3 sports
- [`core-athletes-id-contracts-id`](./core-athletes-id-contracts-id.md) — 2 responses, 2 sports
- [`core-athletes-id-leagues`](./core-athletes-id-leagues.md) — 6 responses, 2 sports
- [`core-competition-plays-id-personnel`](./core-competition-plays-id-personnel.md) — 2 responses, 2 sports
- [`core-competition-statistics`](./core-competition-statistics.md) — 3 responses, 2 sports
- [`core-competitor-status`](./core-competitor-status.md) — 3 responses, 2 sports
- [`core-countries-id`](./core-countries-id.md) — 7 responses, 2 sports
- [`core-countries-id-athletes`](./core-countries-id-athletes.md) — 7 responses, 2 sports
- [`core-franchises-id-awards`](./core-franchises-id-awards.md) — 2 responses, 2 sports
- [`core-season-draft`](./core-season-draft.md) — 3 responses, 2 sports
- [`core-season-draft-athletes`](./core-season-draft-athletes.md) — 3 responses, 2 sports
- [`core-season-draft-athletes-id`](./core-season-draft-athletes-id.md) — 3 responses, 2 sports
- [`core-season-draft-rounds`](./core-season-draft-rounds.md) — 3 responses, 2 sports
- [`core-season-draft-rounds-id-picks-id`](./core-season-draft-rounds-id-picks-id.md) — 3 responses, 2 sports
- [`core-season-draft-status`](./core-season-draft-status.md) — 3 responses, 2 sports
- [`core-season-teams-id-depthcharts`](./core-season-teams-id-depthcharts.md) — 2 responses, 2 sports
- [`core-season-types-id-athletes-id-records-id`](./core-season-types-id-athletes-id-records-id.md) — 4 responses, 2 sports
- [`core-season-types-id-standings`](./core-season-types-id-standings.md) — 4 responses, 2 sports
- [`core-season-types-id-standings-id`](./core-season-types-id-standings-id.md) — 4 responses, 2 sports
- [`core-season-types-id-teams-id-ats`](./core-season-types-id-teams-id-ats.md) — 4 responses, 2 sports
- [`core-season-types-id-teams-id-odds-records`](./core-season-types-id-teams-id-odds-records.md) — 3 responses, 2 sports
- [`core-season-types-id-weeks-id-teams-id-ranks`](./core-season-types-id-weeks-id-teams-id-ranks.md) — 3 responses, 2 sports
- [`core-tournaments`](./core-tournaments.md) — 4 responses, 2 sports
- [`core-tournaments-id`](./core-tournaments-id.md) — 4 responses, 2 sports
- [`core-tournaments-id-seasons`](./core-tournaments-id-seasons.md) — 4 responses, 2 sports
- [`core-athletes-id-competitions`](./core-athletes-id-competitions.md) — 2 responses, 1 sports
- [`core-athletes-id-eventlog`](./core-athletes-id-eventlog.md) — 2 responses, 1 sports
- [`core-athletes-id-events`](./core-athletes-id-events.md) — 7 responses, 1 sports
- [`core-athletes-id-records`](./core-athletes-id-records.md) — 2 responses, 1 sports
- [`core-athletes-id-records-id`](./core-athletes-id-records-id.md) — 2 responses, 1 sports
- [`core-athletes-id-transactions`](./core-athletes-id-transactions.md) — 1 responses, 1 sports
- [`core-circuits-id`](./core-circuits-id.md) — 1 responses, 1 sports
- [`core-competition-commentaries`](./core-competition-commentaries.md) — 7 responses, 1 sports
- [`core-competition-commentaries-id`](./core-competition-commentaries-id.md) — 7 responses, 1 sports
- [`core-competition-commentaries-id-comments`](./core-competition-commentaries-id-comments.md) — 7 responses, 1 sports
- [`core-competition-commentaries-id-comments-id`](./core-competition-commentaries-id-comments-id.md) — 7 responses, 1 sports
- [`core-competition-drives`](./core-competition-drives.md) — 1 responses, 1 sports
- [`core-competition-drives-id`](./core-competition-drives-id.md) — 1 responses, 1 sports
- [`core-competition-drives-id-plays`](./core-competition-drives-id-plays.md) — 1 responses, 1 sports
- [`core-competition-manufacturers-id-statistics`](./core-competition-manufacturers-id-statistics.md) — 1 responses, 1 sports
- [`core-competition-manufacturers-id-statistics-id`](./core-competition-manufacturers-id-statistics-id.md) — 1 responses, 1 sports
- [`core-competition-momentum`](./core-competition-momentum.md) — 1 responses, 1 sports
- [`core-competitor-roster--6626-statistics-id`](./core-competitor-roster--6626-statistics-id.md) — 1 responses, 1 sports
- [`core-competitor-roster-id`](./core-competitor-roster-id.md) — 1 responses, 1 sports
- [`core-event-courses-id`](./core-event-courses-id.md) — 2 responses, 1 sports
- [`core-event-courses-id-rounds-id-statistics`](./core-event-courses-id-rounds-id-statistics.md) — 2 responses, 1 sports
- [`core-franchises--1`](./core-franchises--1.md) — 2 responses, 1 sports
- [`core-franchises--2`](./core-franchises--2.md) — 2 responses, 1 sports
- [`core-groups-id`](./core-groups-id.md) — 7 responses, 1 sports
- [`core-season-athletes--6626`](./core-season-athletes--6626.md) — 1 responses, 1 sports
- [`core-season-athletes--6626-eventlog`](./core-season-athletes--6626-eventlog.md) — 1 responses, 1 sports
- [`core-season-athletes--6626-notes`](./core-season-athletes--6626-notes.md) — 1 responses, 1 sports
- [`core-season-athletes-id-injuries--191006`](./core-season-athletes-id-injuries--191006.md) — 1 responses, 1 sports
- [`core-season-athletes-id-injuries--191107`](./core-season-athletes-id-injuries--191107.md) — 1 responses, 1 sports
- [`core-season-athletes-id-injuries--191352`](./core-season-athletes-id-injuries--191352.md) — 1 responses, 1 sports
- [`core-season-athletes-id-injuries--191400`](./core-season-athletes-id-injuries--191400.md) — 1 responses, 1 sports
- [`core-season-athletes-id-injuries--191483`](./core-season-athletes-id-injuries--191483.md) — 1 responses, 1 sports
- [`core-season-athletes-id-injuries--201144`](./core-season-athletes-id-injuries--201144.md) — 1 responses, 1 sports
- [`core-season-athletes-id-injuries--206324`](./core-season-athletes-id-injuries--206324.md) — 1 responses, 1 sports
- [`core-season-athletes-id-injuries--206329`](./core-season-athletes-id-injuries--206329.md) — 1 responses, 1 sports
- [`core-season-athletes-id-injuries--55039`](./core-season-athletes-id-injuries--55039.md) — 1 responses, 1 sports
- [`core-season-manufacturers-id`](./core-season-manufacturers-id.md) — 1 responses, 1 sports
- [`core-season-manufacturers-id-eventlog`](./core-season-manufacturers-id-eventlog.md) — 1 responses, 1 sports
- [`core-season-players-id-ranks`](./core-season-players-id-ranks.md) — 2 responses, 1 sports
- [`core-season-powerindex`](./core-season-powerindex.md) — 3 responses, 1 sports
- [`core-season-powerindex-leaders`](./core-season-powerindex-leaders.md) — 3 responses, 1 sports
- [`core-season-teams--1`](./core-season-teams--1.md) — 2 responses, 1 sports
- [`core-season-teams--1-athletes`](./core-season-teams--1-athletes.md) — 2 responses, 1 sports
- [`core-season-teams--1-ranks`](./core-season-teams--1-ranks.md) — 2 responses, 1 sports
- [`core-season-teams--2`](./core-season-teams--2.md) — 2 responses, 1 sports
- [`core-season-teams--2-athletes`](./core-season-teams--2-athletes.md) — 2 responses, 1 sports
- [`core-season-teams--2-ranks`](./core-season-teams--2-ranks.md) — 2 responses, 1 sports
- [`core-season-teams-id-summary`](./core-season-teams-id-summary.md) — 7 responses, 1 sports
- [`core-season-transactions`](./core-season-transactions.md) — 7 responses, 1 sports
- [`core-season-types-id-athletes-id-projections`](./core-season-types-id-athletes-id-projections.md) — 1 responses, 1 sports
- [`core-season-types-id-calendar-blacklist`](./core-season-types-id-calendar-blacklist.md) — 7 responses, 1 sports
- [`core-season-types-id-calendar-offdays`](./core-season-types-id-calendar-offdays.md) — 7 responses, 1 sports
- [`core-season-types-id-calendar-ondays`](./core-season-types-id-calendar-ondays.md) — 7 responses, 1 sports
- [`core-season-types-id-calendar-whitelist`](./core-season-types-id-calendar-whitelist.md) — 7 responses, 1 sports
- [`core-season-types-id-teams-id-attendance`](./core-season-types-id-teams-id-attendance.md) — 1 responses, 1 sports
- [`core-season-types-id-teams-id-summary`](./core-season-types-id-teams-id-summary.md) — 7 responses, 1 sports
- [`core-season-types-id-weeks-id-events`](./core-season-types-id-weeks-id-events.md) — 1 responses, 1 sports
- [`core-seasons-powerindex`](./core-seasons-powerindex.md) — 1 responses, 1 sports
- [`core-talentpicks`](./core-talentpicks.md) — 1 responses, 1 sports
- [`core-teams--1-notes`](./core-teams--1-notes.md) — 2 responses, 1 sports
- [`core-teams--2-notes`](./core-teams--2-notes.md) — 2 responses, 1 sports
- [`core-teams-id`](./core-teams-id.md) — 3 responses, 1 sports
- [`core-teams-id-coaches`](./core-teams-id-coaches.md) — 2 responses, 1 sports
- [`core-teams-id-seasons`](./core-teams-id-seasons.md) — 7 responses, 1 sports
- [`core-tournaments-id-seasons-id-bracketology`](./core-tournaments-id-seasons-id-bracketology.md) — 1 responses, 1 sports

## Endpoint support by sport

Cell = successful / attempted requests. `—` = every attempt failed (a 404/400 — for the site API, the tier genuinely does not exist for that sport; for the core graph, no reachable resource linked to it). `·` = not attempted for that sport.

### Site / summary API

| sport | golf-playersummary | injuries | news | rankings | scoreboard | standings | summary | team-roster | team-schedule | team-stats | teams |
|---|---|---|---|---|---|---|---|---|---|---|---|
| australian-football | · | 1/1 | 1/1 | · | 14/14 | 2/2 | 4/4 | 2/2 | 1/1 | — | 1/1 |
| baseball | · | 1/1 | 1/1 | · | 14/14 | 2/2 | 4/4 | 2/2 | 1/1 | 1/1 | 1/1 |
| basketball | · | 3/3 | 3/3 | 1/1 | 42/42 | 6/6 | 12/12 | 6/6 | 3/3 | 3/3 | 3/3 |
| cricket | · | · | 1/1 | · | 14/14 | 2/2 | 1/1 | · | · | · | — |
| field-hockey | · | · | 1/1 | · | 14/14 | 2/2 | 3/4 | · | · | · | 1/1 |
| football | · | 2/2 | 2/2 | 1/1 | 28/28 | 4/4 | 8/8 | 4/4 | 2/2 | 1/2 | 2/2 |
| golf | 2/2 | · | 2/2 | · | 28/28 | 4/4 | — | · | · | · | 2/2 |
| hockey | · | 1/1 | 1/1 | · | 14/14 | 2/2 | 4/4 | 2/2 | 1/1 | 1/1 | 1/1 |
| lacrosse | · | 2/2 | 2/2 | · | 28/28 | 4/4 | 8/8 | 4/4 | 2/2 | — | 2/2 |
| mma | · | · | 2/2 | 1/1 | 28/28 | 4/4 | — | · | · | · | 2/2 |
| racing | · | 1/1 | 2/2 | · | 28/28 | 4/4 | — | 2/2 | 1/1 | — | 2/2 |
| rugby | · | 2/2 | 2/2 | · | 28/28 | 4/4 | 6/6 | 4/4 | — | — | 2/2 |
| rugby-league | · | 1/1 | 1/1 | · | 14/14 | 2/2 | 4/4 | 2/2 | — | — | 1/1 |
| soccer | · | 7/7 | 7/7 | · | 98/98 | 14/14 | 28/28 | 14/14 | 7/7 | 7/7 | 7/7 |
| tennis | · | · | 2/2 | 2/2 | 28/28 | 4/4 | — | · | · | · | 2/2 |
| volleyball | · | 2/2 | 2/2 | · | 27/28 | 4/4 | 8/8 | 4/4 | 2/2 | — | 2/2 |
| water-polo | · | · | 2/2 | · | 28/28 | 4/4 | 5/5 | · | · | · | 2/2 |

### Core API resource graph

Transposed (resource shapes as rows, sports as columns) since the graph has far more shapes than sports. Sorted by breadth — the cross-sport resources (competition, competitor, season …) surface first; the tail is sport-specific. A populated row that used to read `—` under the old URL-guessing crawler (e.g. tennis odds/linescores) is the whole point: those resources were always there, just not at a guessable URL.

| resource | australian-football | baseball | basketball | cricket | field-hockey | football | golf | hockey | lacrosse | mma | racing | rugby | rugby-league | soccer | tennis | volleyball | water-polo |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `core-calendar` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | 2/2 | 1/1 | 2/2 | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-competition` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | 2/2 | 1/1 | 2/2 | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-competition-status` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | 2/2 | 1/1 | 2/2 | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-competitor` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | 2/2 | 1/1 | 2/2 | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-event` | 1/1 | 1/1 | 3/3 | — | 1/1 | 2/2 | 2/2 | 1/1 | 2/2 | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-events` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | 2/2 | 1/1 | 2/2 | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-league` | 1/1 | 1/1 | 3/3 | — | 1/1 | 2/2 | 2/2 | 1/1 | 2/2 | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-season` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | 2/2 | 1/1 | 2/2 | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-season-type` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | 2/2 | 1/1 | 2/2 | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-season-types` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | 2/2 | 1/1 | 2/2 | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-seasons` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | 2/2 | 1/1 | 2/2 | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-calendar-blacklist` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | 2/2 | 1/1 | 2/2 | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-calendar-offdays` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | 2/2 | 1/1 | 2/2 | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-calendar-ondays` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | 2/2 | 1/1 | 2/2 | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-calendar-whitelist` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | 2/2 | 1/1 | 2/2 | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-competition-broadcasts` | · | 1/1 | 3/3 | · | 1/1 | 2/2 | 2/2 | 1/1 | 1/1 | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-competitor-linescores` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | 2/2 | 1/1 | 2/2 | 1/1 | · | 1/1 | 1/1 | 7/7 | 2/2 | 2/2 | 1/1 |
| `core-competitor-score` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | 2/2 | 1/1 | 2/2 | · | · | 2/2 | 1/1 | 7/7 | · | 2/2 | 2/2 |
| `core-competitor-scores-id` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | 2/2 | 1/1 | 2/2 | · | · | 2/2 | 1/1 | 7/7 | · | 2/2 | 2/2 |
| `core-media-id` | · | 1/1 | 3/3 | · | 1/1 | 2/2 | 2/2 | 1/1 | 1/1 | 2/2 | 2/2 | · | · | 6/6 | 2/2 | 2/2 | 2/2 |
| `core-competitor-linescores-id-id` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | 2/2 | · | · | 1/1 | 1/1 | 7/7 | 2/2 | 2/2 | 1/1 |
| `core-rankings` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | · | · | 2/2 | · | · | 2/2 | 1/1 | 7/7 | 2/2 | 2/2 | 2/2 |
| `core-season-teams` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | · | 1/1 | 2/2 | · | · | 2/2 | 1/1 | 7/7 | · | 2/2 | 2/2 |
| `core-season-teams-id` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | · | 1/1 | 2/2 | · | · | 2/2 | 1/1 | 7/7 | · | 2/2 | 2/2 |
| `core-season-types-id-teams-id-record` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | · | 1/1 | 2/2 | · | · | 2/2 | 1/1 | 7/7 | · | 1/1 | 2/2 |
| `core-season-types-id-teams-id-records-id` | 1/1 | 1/1 | 3/3 | · | 1/1 | 1/1 | · | 1/1 | 1/1 | · | · | 2/2 | 1/1 | 5/5 | · | 1/1 | 2/2 |
| `core-venues-id` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | 2/2 | 1/1 | · | 2/2 | 2/2 | 2/2 | 1/1 | 7/7 | · | 2/2 | · |
| `core-competitor-statistics-id` | 1/1 | 1/1 | 3/3 | · | · | 1/1 | 2/2 | 1/1 | · | 1/1 | 2/2 | 1/1 | 1/1 | 7/7 | · | · | · |
| `core-season-athletes-id-eventlog` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | 2/2 | 1/1 | · | · | 2/2 | 1/1 | 1/1 | 7/7 | 2/2 | · | · |
| `core-season-teams-id-events` | 1/1 | 1/1 | 3/3 | · | 1/1 | 1/1 | · | 1/1 | 2/2 | · | · | 2/2 | 1/1 | 7/7 | · | · | 2/2 |
| `core-season-types-id-groups` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | · | 1/1 | 2/2 | · | · | 2/2 | 1/1 | 7/7 | · | 2/2 | · |
| `core-season-types-id-groups-id` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | · | 1/1 | 2/2 | · | · | 2/2 | 1/1 | 7/7 | · | 2/2 | · |
| `core-competitor-statistics` | · | 1/1 | 3/3 | · | · | 1/1 | 2/2 | 1/1 | · | 1/1 | 2/2 | 1/1 | 1/1 | 7/7 | · | · | · |
| `core-notes` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | 2/2 | · | · | 2/2 | 1/1 | 7/7 | · | 2/2 | · |
| `core-season-athletes-id` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | 2/2 | 1/1 | · | · | 2/2 | 1/1 | 1/1 | 7/7 | · | · | · |
| `core-season-rankings` | 1/1 | 1/1 | 3/3 | · | 1/1 | 2/2 | · | 1/1 | 2/2 | · | · | · | · | · | 2/2 | 2/2 | 2/2 |
| `core-season-types-id-athletes-id-statistics-id` | 1/1 | 1/1 | 3/3 | · | · | 1/1 | 2/2 | 1/1 | · | · | · | 1/1 | 1/1 | 1/1 | 2/2 | · | · |
| `core-season-types-id-groups-id-children` | · | 1/1 | 3/3 | · | 1/1 | 2/2 | · | 1/1 | 1/1 | · | · | 2/2 | 1/1 | 7/7 | · | 1/1 | · |
| `core-competition-plays-id` | 1/1 | 1/1 | 3/3 | · | · | 1/1 | · | 1/1 | · | 1/1 | · | 1/1 | 1/1 | 7/7 | · | · | · |
| `core-competition-relevancy` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | · | · | · | 2/2 | 1/1 | 7/7 | · | 2/2 | · |
| `core-competitor-roster` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | · | · | · | 1/1 | 1/1 | 7/7 | 2/2 | · | · |
| `core-plays` | 1/1 | 1/1 | 3/3 | · | · | 1/1 | · | 1/1 | · | 1/1 | · | 2/2 | 1/1 | 7/7 | · | · | · |
| `core-season-teams-id-athletes` | 1/1 | 1/1 | 3/3 | · | · | 1/1 | · | 1/1 | · | · | · | 1/1 | 1/1 | 7/7 | · | 1/1 | · |
| `core-season-types-id-athletes-id-statistics` | 1/1 | 1/1 | 3/3 | · | · | · | 2/2 | 1/1 | · | · | · | 1/1 | 1/1 | 1/1 | 2/2 | · | · |
| `core-situation` | 1/1 | 1/1 | 3/3 | · | · | 1/1 | · | 1/1 | · | · | · | 2/2 | 1/1 | 7/7 | · | 2/2 | · |
| `core-competitor-leaders` | 1/1 | 1/1 | 3/3 | · | · | 1/1 | · | 1/1 | · | · | · | 2/2 | 1/1 | 7/7 | · | · | · |
| `core-competitor-records` | 1/1 | 1/1 | 1/1 | · | 1/1 | 1/1 | · | · | 2/2 | · | · | · | · | 5/5 | · | 1/1 | · |
| `core-competitor-records-id` | 1/1 | 1/1 | 1/1 | · | 1/1 | 1/1 | · | · | 2/2 | · | · | · | · | 5/5 | · | 1/1 | · |
| `core-competitor-roster-id-statistics-id` | 1/1 | 1/1 | 3/3 | · | · | 1/1 | · | 1/1 | · | · | · | 1/1 | 1/1 | 7/7 | · | · | · |
| `core-franchises` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | 2/2 | · | · | · | · | 7/7 | · | 2/2 | · |
| `core-franchises-id` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | 2/2 | · | · | · | · | 7/7 | · | 2/2 | · |
| `core-league-athletes` | · | 1/1 | 2/2 | · | · | 1/1 | 2/2 | 1/1 | · | · | · | 2/2 | 1/1 | · | · | 2/2 | · |
| `core-odds` | · | 1/1 | 3/3 | · | · | 1/1 | · | 1/1 | · | · | · | 2/2 | 1/1 | 7/7 | 2/2 | · | · |
| `core-positions-id` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | · | · | · | 1/1 | 1/1 | 7/7 | · | · | · |
| `core-season-athletes-id-notes` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | · | · | · | 1/1 | 1/1 | 7/7 | · | · | · |
| `core-season-types-id-teams-id-athletes-id-statistics-id` | 1/1 | 1/1 | 3/3 | · | · | 1/1 | · | 1/1 | · | · | · | 1/1 | 1/1 | 7/7 | · | · | · |
| `core-season-types-id-teams-id-leaders` | 1/1 | 1/1 | 3/3 | · | · | 1/1 | · | 1/1 | · | · | · | 1/1 | 1/1 | 7/7 | · | · | · |
| `core-teams-id-notes` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | · | · | · | · | · | 2/2 | 1/1 | 7/7 | · | 2/2 | · |
| `core-athletes-id` | · | 1/1 | 2/2 | · | · | 1/1 | 2/2 | 1/1 | · | · | · | · | 1/1 | · | · | 1/1 | · |
| `core-season-athletes` | · | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | · | · | 2/2 | · | · | 7/7 | 2/2 | · | · |
| `core-season-types-id-groups-id-standings` | 1/1 | 1/1 | 2/2 | · | · | 2/2 | · | 1/1 | 2/2 | · | · | · | · | · | · | 2/2 | · |
| `core-season-types-id-groups-id-standings-id` | 1/1 | 1/1 | 2/2 | · | · | 2/2 | · | 1/1 | 2/2 | · | · | · | · | · | · | 2/2 | · |
| `core-season-types-id-weeks` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | · | · | · | · | 1/1 | · | · | 2/2 | · |
| `core-transactions` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | · | · | 2/2 | · | · | · | · | · | 2/2 | 2/2 | · |
| `core-athletes-id-contracts` | 1/1 | 1/1 | 2/2 | · | · | 1/1 | · | 1/1 | · | · | · | · | · | · | · | 1/1 | · |
| `core-season-types-id-groups-id-teams` | · | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | 2/2 | · | · | · | · | · | · | 2/2 | · |
| `core-season-types-id-teams-id-statistics` | 1/1 | 1/1 | 3/3 | · | · | 1/1 | · | 1/1 | · | · | · | · | · | 7/7 | · | · | · |
| `core-season-types-id-teams-id-statistics-id` | 1/1 | 1/1 | 3/3 | · | · | 1/1 | · | 1/1 | · | · | · | · | · | 7/7 | · | · | · |
| `core-season-types-id-weeks-id` | 1/1 | 1/1 | 2/2 | · | · | 2/2 | · | · | · | · | · | · | 1/1 | · | · | 2/2 | · |
| `core-season-types-id-weeks-id-rankings` | 1/1 | 1/1 | 2/2 | · | · | 2/2 | · | · | · | · | · | · | 1/1 | · | · | 2/2 | · |
| `core-teams-id-injuries` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | · | · | · | · | · | 7/7 | · | · | · |
| `core-athlete` | · | · | · | · | · | · | · | · | · | 2/2 | 2/2 | 1/1 | 1/1 | · | 2/2 | · | · |
| `core-athletes-id-statistics-id` | · | 1/1 | 2/2 | · | · | 1/1 | · | 1/1 | · | 2/2 | · | · | · | · | · | · | · |
| `core-coaches-id` | · | 1/1 | 2/2 | · | · | 2/2 | · | 1/1 | · | · | · | · | · | 2/2 | · | · | · |
| `core-competition-officials` | · | 1/1 | 3/3 | · | · | · | · | 1/1 | · | 1/1 | · | · | · | 7/7 | · | · | · |
| `core-competition-officials-id` | · | 1/1 | 3/3 | · | · | · | · | 1/1 | · | 1/1 | · | · | · | 2/2 | · | · | · |
| `core-season-teams-id-ranks` | 1/1 | 1/1 | 3/3 | · | · | 2/2 | · | · | · | · | · | · | · | · | · | 2/2 | · |
| `core-season-types-id-groups-id-teams-id-records-id` | 1/1 | 1/1 | 2/2 | · | · | · | · | · | 2/2 | · | · | · | · | · | · | 1/1 | · |
| `core-season-types-id-weeks-id-rankings-id` | · | · | 1/1 | · | 1/1 | 1/1 | · | · | · | · | · | · | · | · | 2/2 | 2/2 | · |
| `core-athletes-id-statistics` | · | 1/1 | 1/1 | · | · | · | · | 1/1 | · | 2/2 | · | · | · | · | · | · | · |
| `core-athletes-id-statisticslog` | · | 1/1 | 1/1 | · | · | · | 4/4 | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-casinos-id` | · | 1/1 | 2/2 | · | · | · | · | 1/1 | · | · | · | · | · | 7/7 | · | · | · |
| `core-competition-leaders` | 1/1 | 1/1 | · | · | · | 1/1 | 1/1 | · | · | · | · | · | · | · | · | · | · |
| `core-competition-odds-id` | · | · | 3/3 | · | · | 1/1 | · | 1/1 | · | · | · | · | · | 7/7 | · | · | · |
| `core-competition-odds-id-propBets` | · | 1/1 | 2/2 | · | · | · | · | 1/1 | · | · | · | · | · | 7/7 | · | · | · |
| `core-providers-id` | · | · | 3/3 | · | · | 1/1 | · | 1/1 | · | · | · | · | · | 7/7 | · | · | · |
| `core-season-athletes-id-injuries-id` | 1/1 | 1/1 | 2/2 | · | · | · | · | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-season-awards-id` | · | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-season-coaches` | · | 1/1 | 1/1 | · | · | 1/1 | · | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-season-coaches-id` | · | 1/1 | 2/2 | · | · | 2/2 | · | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-season-futures` | · | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-season-futures-id` | · | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-season-teams-id-awards` | · | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-season-teams-id-coaches` | · | 1/1 | 2/2 | · | · | 1/1 | · | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-season-types-id-corrections` | · | 1/1 | 1/1 | · | · | 1/1 | · | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-season-types-id-leaders` | · | 1/1 | 3/3 | · | · | 2/2 | · | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-tournaments-id-seasons-id` | · | · | 1/1 | · | · | · | 2/2 | · | · | · | · | · | · | 2/2 | 2/2 | · | · |
| `core-athletes-id-seasons` | · | · | 1/1 | · | · | · | 2/2 | · | · | · | · | · | · | 3/3 | · | · | · |
| `core-awards` | · | 1/1 | 3/3 | · | · | 2/2 | · | · | · | · | · | · | · | · | · | · | · |
| `core-awards-id` | · | 1/1 | 3/3 | · | · | 2/2 | · | · | · | · | · | · | · | · | · | · | · |
| `core-coaches-id-record-id` | · | 1/1 | 1/1 | · | · | 2/2 | · | · | · | · | · | · | · | · | · | · | · |
| `core-competition-powerindex` | · | 1/1 | 3/3 | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-competition-probabilities-id` | · | 1/1 | 3/3 | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-competitor-roster-id-projections` | · | 1/1 | 1/1 | · | · | · | · | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-leaders` | · | 1/1 | 1/1 | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-leaders-id` | · | 1/1 | 1/1 | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-powerindex` | · | 1/1 | 3/3 | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-predictor` | · | 1/1 | 3/3 | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-probabilities` | · | 1/1 | 3/3 | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-awards` | · | · | 3/3 | · | · | 2/2 | · | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-season-freeagents` | · | 1/1 | · | · | · | 1/1 | · | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-season-rankings-id` | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · | 2/2 | 1/1 | · |
| `core-season-teams-id-transactions` | · | 1/1 | 1/1 | · | · | · | · | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-season-types-id-coaches-id-record` | · | 1/1 | 1/1 | · | · | 2/2 | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-types-id-teams-id-athletes-id-statistics` | · | 1/1 | 1/1 | · | · | · | · | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-season-types-id-weeks-id-teams-id-ranks-id` | · | · | 1/1 | · | · | 1/1 | · | · | · | · | · | · | · | · | · | 2/2 | · |
| `core-athletes-id-contracts-id` | · | · | 1/1 | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-athletes-id-leagues` | · | · | · | · | · | · | · | · | · | 2/2 | · | · | · | 4/4 | · | · | · |
| `core-competition-plays-id-personnel` | · | · | 1/1 | · | · | · | · | 1/1 | · | · | · | · | · | · | · | · | · |
| `core-competition-statistics` | 1/1 | · | · | · | · | · | · | · | · | · | 2/2 | · | · | · | · | · | · |
| `core-competitor-status` | · | · | · | · | · | · | 2/2 | · | · | · | 1/1 | · | · | · | · | · | · |
| `core-countries-id` | · | · | · | · | · | · | 2/2 | · | · | · | · | · | · | 5/5 | · | · | · |
| `core-countries-id-athletes` | · | · | · | · | · | · | 2/2 | · | · | · | · | · | · | 5/5 | · | · | · |
| `core-franchises-id-awards` | · | 1/1 | · | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-draft` | · | · | 2/2 | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-draft-athletes` | · | · | 2/2 | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-draft-athletes-id` | · | · | 2/2 | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-draft-rounds` | · | · | 2/2 | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-draft-rounds-id-picks-id` | · | · | 2/2 | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-draft-status` | · | · | 2/2 | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-teams-id-depthcharts` | · | 1/1 | 1/1 | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-types-id-athletes-id-records-id` | · | · | · | · | · | · | 2/2 | · | · | · | 2/2 | · | · | · | · | · | · |
| `core-season-types-id-standings` | · | · | · | · | · | · | 2/2 | · | · | · | 2/2 | · | · | · | · | · | · |
| `core-season-types-id-standings-id` | · | · | · | · | · | · | 2/2 | · | · | · | 2/2 | · | · | · | · | · | · |
| `core-season-types-id-teams-id-ats` | · | · | 2/2 | · | · | 2/2 | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-types-id-teams-id-odds-records` | · | 1/1 | 2/2 | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-types-id-weeks-id-teams-id-ranks` | · | · | · | · | · | 1/1 | · | · | · | · | · | · | · | · | · | 2/2 | · |
| `core-tournaments` | · | · | · | · | · | · | 2/2 | · | · | · | · | · | · | · | 2/2 | · | · |
| `core-tournaments-id` | · | · | · | · | · | · | 2/2 | · | · | · | · | · | · | · | 2/2 | · | · |
| `core-tournaments-id-seasons` | · | · | · | · | · | · | 2/2 | · | · | · | · | · | · | · | 2/2 | · | · |
| `core-athletes-id-competitions` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 2/2 | · | · |
| `core-athletes-id-eventlog` | · | · | · | · | · | · | · | · | · | 2/2 | · | · | · | · | · | · | · |
| `core-athletes-id-events` | · | · | · | · | · | · | · | · | · | · | · | · | · | 7/7 | · | · | · |
| `core-athletes-id-records` | · | · | · | · | · | · | · | · | · | 2/2 | · | · | · | · | · | · | · |
| `core-athletes-id-records-id` | · | · | · | · | · | · | · | · | · | 2/2 | · | · | · | · | · | · | · |
| `core-athletes-id-transactions` | · | · | · | · | · | · | · | · | · | · | · | · | · | 1/1 | · | · | · |
| `core-circuits-id` | · | · | · | · | · | · | · | · | · | · | 1/1 | · | · | · | · | · | · |
| `core-competition-commentaries` | · | · | · | · | · | · | · | · | · | · | · | · | · | 7/7 | · | · | · |
| `core-competition-commentaries-id` | · | · | · | · | · | · | · | · | · | · | · | · | · | 7/7 | · | · | · |
| `core-competition-commentaries-id-comments` | · | · | · | · | · | · | · | · | · | · | · | · | · | 7/7 | · | · | · |
| `core-competition-commentaries-id-comments-id` | · | · | · | · | · | · | · | · | · | · | · | · | · | 7/7 | · | · | · |
| `core-competition-drives` | · | · | · | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-competition-drives-id` | · | · | · | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-competition-drives-id-plays` | · | · | · | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-competition-manufacturers-id-statistics` | · | · | · | · | · | · | · | · | · | · | 1/1 | · | · | · | · | · | · |
| `core-competition-manufacturers-id-statistics-id` | · | · | · | · | · | · | · | · | · | · | 1/1 | · | · | · | · | · | · |
| `core-competition-momentum` | · | · | · | · | · | · | · | · | · | · | · | · | · | 1/1 | · | · | · |
| `core-competitor-roster--6626-statistics-id` | · | · | · | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-competitor-roster-id` | · | · | · | · | · | · | · | · | · | · | · | · | · | 1/1 | · | · | · |
| `core-event-courses-id` | · | · | · | · | · | · | 2/2 | · | · | · | · | · | · | · | · | · | · |
| `core-event-courses-id-rounds-id-statistics` | · | · | · | · | · | · | 2/2 | · | · | · | · | · | · | · | · | · | · |
| `core-franchises--1` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 2/2 | · |
| `core-franchises--2` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 2/2 | · |
| `core-groups-id` | · | · | · | · | · | · | · | · | · | · | · | · | · | 7/7 | · | · | · |
| `core-season-athletes--6626` | · | · | · | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-athletes--6626-eventlog` | · | · | · | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-athletes--6626-notes` | · | · | · | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-athletes-id-injuries--191006` | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-athletes-id-injuries--191107` | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-athletes-id-injuries--191352` | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-athletes-id-injuries--191400` | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-athletes-id-injuries--191483` | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-athletes-id-injuries--201144` | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-athletes-id-injuries--206324` | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-athletes-id-injuries--206329` | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-athletes-id-injuries--55039` | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-manufacturers-id` | · | · | · | · | · | · | · | · | · | · | 1/1 | · | · | · | · | · | · |
| `core-season-manufacturers-id-eventlog` | · | · | · | · | · | · | · | · | · | · | 1/1 | · | · | · | · | · | · |
| `core-season-players-id-ranks` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 2/2 | · | · |
| `core-season-powerindex` | · | · | 3/3 | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-powerindex-leaders` | · | · | 3/3 | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-teams--1` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 2/2 | · |
| `core-season-teams--1-athletes` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 2/2 | · |
| `core-season-teams--1-ranks` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 2/2 | · |
| `core-season-teams--2` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 2/2 | · |
| `core-season-teams--2-athletes` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 2/2 | · |
| `core-season-teams--2-ranks` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 2/2 | · |
| `core-season-teams-id-summary` | · | · | · | · | · | · | · | · | · | · | · | · | · | 7/7 | · | · | · |
| `core-season-transactions` | · | · | · | · | · | · | · | · | · | · | · | · | · | 7/7 | · | · | · |
| `core-season-types-id-athletes-id-projections` | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-types-id-calendar-blacklist` | · | · | · | · | · | · | · | · | · | · | · | · | · | 7/7 | · | · | · |
| `core-season-types-id-calendar-offdays` | · | · | · | · | · | · | · | · | · | · | · | · | · | 7/7 | · | · | · |
| `core-season-types-id-calendar-ondays` | · | · | · | · | · | · | · | · | · | · | · | · | · | 7/7 | · | · | · |
| `core-season-types-id-calendar-whitelist` | · | · | · | · | · | · | · | · | · | · | · | · | · | 7/7 | · | · | · |
| `core-season-types-id-teams-id-attendance` | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `core-season-types-id-teams-id-summary` | · | · | · | · | · | · | · | · | · | · | · | · | · | 7/7 | · | · | · |
| `core-season-types-id-weeks-id-events` | · | · | · | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-seasons-powerindex` | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `core-talentpicks` | · | · | · | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · |
| `core-teams--1-notes` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 2/2 | · |
| `core-teams--2-notes` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 2/2 | · |
| `core-teams-id` | · | · | · | · | · | · | · | · | · | · | · | · | · | 3/3 | · | · | · |
| `core-teams-id-coaches` | · | · | · | · | · | · | · | · | · | · | · | · | · | 2/2 | · | · | · |
| `core-teams-id-seasons` | · | · | · | · | · | · | · | · | · | · | · | · | · | 7/7 | · | · | · |
| `core-tournaments-id-seasons-id-bracketology` | · | · | 1/1 | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
