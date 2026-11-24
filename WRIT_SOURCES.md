# Writ data provenance

Checked 2026-11-24. Initial seed: 1 cross-checked entry out of 150 reported by https://aidvir.github.io/wow-forever-favor/writs.html. The other 149 are not included pending row-level verification. No in-game testing yet.

## 264018 — Elixir of Defense

- Writ ID, name, tier: https://www.wowhead.com/forever/item=264018/craftsmans-writ-elixir-of-defense
- Quest ID 94218, both factions, daily, one Writ and one Elixir of Defense, 75 reputation, Rizzle Brassbolts: https://db.icy-veins.com/wow-forever/quests/94218
- Corroboration of reward, faction and zone: https://questing.wiki/wow-forever/quests/94218/
- Required item ID 8951 and quantity one, profession: https://www.foreverdb.app/en/forever/items/8951/elixir-of-defense
- Client-derived item ID corroboration: https://wowforeverhelper.com/item/8951/elixir-of-defense
- Tier, NPC, zone and profession corroboration: https://www.wowhead.com/forever/guide/professions/craftsmans-writs-overview-recipes-rewards

Coordinates omitted because sources disagree. Coin pouch amounts omitted because variable. Do not use Classic Era item names to resolve Forever IDs: 3389 is renamed Elixir of Lesser Defense, not the requested item.

## Inclusion rules

Require row-level evidence for Writ ID, quest ID, requested item IDs and quantities, reputation, tier, faction eligibility and daily status. Cross-check against separate sources where possible; shared upstream datasets are not independent live observations. Record NPC/zone only when supported, omit uncertain optional fields. Do not infer IDs from neighboring IDs. Do not include sealed envelopes as deterministic Writs. Use factual fields only, not copied third-party code or quest text. Review source licenses before bulk imports. Confirm against the live client before stable release.

The seed is intentionally not in the TOC until integration and validation.

## Bulk comparison (2026-11-24)
Compared all 150 IDs in AidVir/wow-forever-favor data/writs.js and emsw0rth/craftmanshelper CraftmansHelper/Data/Writs.lua with buildthehomelab/wow-mod-supply-logistics data/writs.tsv. 146 matched item, quest, quantity, tier/reward and profession association. Four absent from the TSV: 264065, 264069, 264124, 264139. No IDs inferred. The candidate TSV is research only, not loaded by the addon. Faction is a single-source hint, including the default Both, and must be confirmed against individual quest records before promotion. Shared upstream data limits independence. Daily and tier rules corroborated by Wowhead and Icy Veins; individual daily exceptions remain to be checked.

Sources:
- https://github.com/AidVir/wow-forever-favor/blob/main/data/writs.js (no explicit license located; factual comparison only)
- https://github.com/emsw0rth/craftmanshelper/blob/main/CraftmansHelper/Data/Writs.lua (license not established; factual comparison only)
- https://github.com/buildthehomelab/wow-mod-supply-logistics/blob/main/data/writs.tsv (repository README explicitly identifies Efficient Games EG Link output as CC BY 4.0; adapted numeric fields, filtered and combined with cross-checks; https://creativecommons.org/licenses/by/4.0/). Candidate TSV is distributed under CC BY 4.0 for the adapted dataset, not a change to MFO code licensing.
- https://www.wowhead.com/forever/guide/professions/craftsmans-writs-overview-recipes-rewards
- https://www.icy-veins.com/wow-forever/news/sealed-writs-are-a-daily-source-of-supply-faction-reputation-in-wow-forever/

The active database remains at one entry pending faction checks. No copied source code or quest prose.

## Further quest-level audit
264065 / 94265: Wowhead item page https://www.wowhead.com/forever/item=264065/craftsmans-writ-goblin-rocket-fuel identifies Expert and daily quest. https://guide.wow4ever.se/en/quests/94265 confirms both factions and one fuel plus one writ (EG Link CC BY 4.0). https://zephras.com/forever/enUS/quest/94265/ confirms 125 reputation and turn-in Alchemist Pestlezugg. https://bindonforever.com/quest/94265 corroborates both factions and Tanaris delivery using QuestieDB. Existing two candidate sources agree on item 9061 and quantity one; profession classification remains unresolved (Alchemy versus Alchemy/Engineering). Hold pending explicit profession schema decision. 264069, 264124, 264139 remain excluded. IceDNicco quest index marks many entries faction unavailable; this is not evidence of Both. No blanket promotion of 146 candidates. Regression execution pending.
