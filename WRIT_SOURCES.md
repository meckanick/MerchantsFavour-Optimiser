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
