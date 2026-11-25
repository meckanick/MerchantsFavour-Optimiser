# Writ data provenance

The 2026-11-24 audit reviewed 150 Writs. The generated table contains 130 verified records. Twenty remain excluded because the quest race mask and a faction hint disagree. The audit records raw quest facts and source builds for every Writ, including exclusions. Each Lua `sourceKey` is the corresponding Writ ID in [the audit](research/writ-audit.json).

## What the inputs establish

- [Efficient Games EG Link](https://github.com/JIVESCORP/eg-link-output-wowf/tree/d78a89020881ec338a4a7c1f2a89ee613f68554b) publishes server quest responses collected from Forever clients. The verifier checks the exact file hashes and Forever export metadata. Build 70938 covers all 150 quest IDs, 70959 covers 143, and 71037 covers 145. Where a quest appears in multiple builds, its checked fields must agree. Builds from EG Link share an upstream source.
- The verifier checks both item objectives, the Writ quantity of one, objective item IDs and quantities, both supply reputation overrides and the tier's treasure picker. It reads the daily bit in the base flags and rejects conflicting repeat flags. The extension flags, quest type, minimum level and time limit must match the reviewed Writ profile. See the [EG Link field schema](https://github.com/JIVESCORP/eg-link-output-wowf/blob/d78a89020881ec338a4a7c1f2a89ee613f68554b/DATASETS.md#questslocale) and [Questie flag definitions](https://github.com/Questie/Questie/blob/master/Database/QuestieDB.lua).
- All 150 rows explicitly carry the all-races mask `ffffffffffffffff` and the daily flag. The other accepted masks are the complete Forever faction masks, including each faction's Skyborne bit. Missing, partial and unknown masks fail verification. Quest responses can establish what the race mask says. NPC availability, live turn-in eligibility and server-side requirements outside the export still need in-game checks.
- [The logistics TSV](https://github.com/buildthehomelab/wow-mod-supply-logistics/blob/178d06486e6e74c64c034b93392474c22d89fc2e/data/writs.tsv) corroborates the candidate quest, objective, quantity and reward. Its skill columns supply profession associations, including both for `264144` (Gordok Ogre Suit). Profession tags describe crafting and recipe supply. They do not express character eligibility.
- The [AidVir Writ index](https://github.com/AidVir/wow-forever-favor/blob/e714f1f25a3fe8983c3af4e8c7985e2a9b8b3596/data/writs.js) (SHA-256 `98bd97855c056986e8643a39649d41271232a4c0ead268696453aa333cc56803`, no explicit license found) and [CraftmansHelper index](https://github.com/emsw0rth/craftmanshelper/blob/4e20664d8bb07a75b917172bb694a56a09588750/CraftmansHelper/Data/Writs.lua) (SHA-256 `5ab5f110e7f4169a42488ad01a70c8504b69b15b0da69fbdf8dbca3921609907`, GPL-3.0) were consulted for factual comparisons only. Their source files are not generator inputs or bundled with MFO. The faction hints in the candidate TSV come from the AidVir comparison. A default Both hint does not establish faction eligibility.

Data from [Efficient Games](https://efficient.games), licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). MFO filters and combines the numeric quest fields with the candidate comparisons and derived tags. The logistics Writ TSV is [separately attributed as CC BY 4.0](https://github.com/buildthehomelab/wow-mod-supply-logistics/blob/178d06486e6e74c64c034b93392474c22d89fc2e/README.md). The generated table and audit omit upstream code, game text, names, and optional NPC and zone labels. MFO's code license is MIT.

## Four Writs absent from the logistics TSV

Each has two item objectives with quantity one, an explicit daily flag and all-races mask, and matching rewards in all three pinned Forever builds.

| Writ | Quest | Requested item | Tier and reputation | Profession evidence |
| --- | --- | --- | --- | --- |
| 264065 | 94265 | 9061 | Expert, 125 | Alchemy crafts Goblin Rocket Fuel. Engineering supplies the recipe. [Forever item](https://guide.wow4ever.se/en/items/9061) · [Engineering recipe](https://www.wowhead.com/forever/guide/professions/engineering-overview-trainer-locations-recipes) |
| 264069 | 94269 | 9060 | Expert, 125 | Blacksmithing crafts Inlaid Mithril Cylinder. Engineering supplies the plans. [Forever item](https://guide.wow4ever.se/en/items/9060) · [Engineering plans](https://wowfdb.com/professions/engineering/recipes/) |
| 264124 | 94324 | 246948 | Artisan, 200 | Alchemy crafts Distilled Firewater. [Forever item and recipe](https://www.foreverdb.app/en/forever/items/246948/distilled-firewater) |
| 264139 | 94339 | 18232 | Artisan, 200 | Engineering crafts Field Repair Bot 74A. [Forever recipe](https://wowforever.ninja/professions/engineering/22704-field-repair-bot-74a/) |

## Exclusions

The pinned quest responses indicate Both for the following IDs. Their faction hints are Alliance or Horde. The three corresponding EG Link turn-in exports had no observations for these quests to resolve the discrepancy.

- Alliance hints (8) — 264011, 264015, 264024, 264025, 264027, 264030, 264033, 264054.
- Horde hints (12) — 264013, 264016, 264020, 264028, 264029, 264031, 264039, 264043, 264044, 264047, 264050, 264055.

The turn-in files are `data/wowf/<build>/turn_ins.json` at the same EG Link revision. SHA-256 values are `b0bdb851d6790e590323432d9f08bef811613a829c03cd68414ad2ecec8899f1` (70938), `329efdcf27854b9a851ed5e0c09712aaa7feeae63de3344a6441e228b19e8659` (70959), and `1bb3dffa767e54087f0242e3b94adfd8ab51ccf75098219a3fc3e3924980b78b` (71037).

## Reproduce the audit

Download the raw source URLs from the audit's `sources` section. Save the three exports as `<build>-quests.enUS.json` and the logistics export as `logistics.tsv` in a local directory. Run from the repository root.

```sh
python tools/verify_writs.py --source-dir raw-inputs --report research/writ-audit.json --lua MerchantsFavourOptimiser/WritData.lua
python -B -m unittest discover -s tests -p 'test_verify_writs.py'
lua5.1 tests/writ-data-regression.lua
```

## Cost calculation

The addon loads the verified records and calculator through its TOC. Use
`MFO_WritCalculations.available(faction, professions)` to filter records, and
`calculateSelection(writIDs, faction, getPrice, getOwned)` to price distinct Writs
against one pool of owned stock. Pass profession names as keys in an optional
set. A Writ appears once if any of its professions match. These associations
describe item and recipe supply. Faction controls turn-in eligibility.

Use a price reader that returns unit copper and a stale flag, such as a closure
calling `MFO_AH.PriceQuote(id, maxAgeSeconds, now)` with a fixed timestamp for the
estimate. A missing or stale price on any purchase makes expenditure and cost
per reputation point unavailable. Owned stock still reduces purchase quantities.
If an owned unit lacks a fresh price, its savings cannot be valued. An entirely
owned selection requires zero expenditure.

The calculator accepts the same item-count callback pattern as the crate
calculator, including counts from `MFO_InventoryProvider.TotalCount`. The Writ
calculator and database still need live-client validation.

## Delivery locations

The 2026-11-25 [delivery audit](research/writ-delivery-audit.tsv) joins the 130
verified quest IDs above to Forever quest and recipient records. It identifies
the source pages per quest and the corroborating publications for each accepted
location. The runtime includes 97 Writs at 73 destinations across 28 zone maps.
Only factual identifiers, names, reactions and coordinates are bundled.

- The [Out of Games Forever database](https://outof.games/realms/forever/quest/94214-craftsmans-writ-shadow-protection-potion/)
  gives the endpoint type and ID, zone and map coordinates. The linked
  [recipient page](https://outof.games/realms/forever/npc/3134-kzixx/) gives the
  spawn and NPC faction reaction. The [AzerDex zone index](https://azerdex.com/zones)
  supplies the Forever `uiMapID` for each zone.
- An included endpoint also agrees with the same quest's hand-in position
  on [BindOnForever](https://bindonforever.com/quest/94214) or the pinned
  CraftmansHelper [quest-to-recipient](https://github.com/emsw0rth/craftmanshelper/blob/b3379665bae02912bafdbfa064e4224c7777679a/CraftmansHelper/Data/Writs.lua)
  and [recipient-to-map](https://github.com/emsw0rth/craftmanshelper/blob/b3379665bae02912bafdbfa064e4224c7777679a/CraftmansHelper/Data/TurnIns.lua)
  references. Replace the numeric quest ID in the BindOnForever URL to reproduce
  its check for a row. The publications can share upstream data. The check
  allows up to 0.25 percentage points per coordinate for reported position
  differences. Map IDs and known recipient IDs must agree.
- Quest `94223` ends at object `642320`, Battered Trunk, on Duskwood map
  `1431` at `26.3, 36.2`. Both factions are listed for the quest. The object
  ID and coordinates agree with the linked object and quest records.
  [Object record](https://outof.games/realms/forever/object/642320-battered-trunk/) ·
  [Quest map](https://bindonforever.com/quest/94223) ·
  [In-game logger](https://www.warcraftforever.wiki/wiki/Battered_Trunk_%28Object%29)
- Of the 33 omissions, 23 lack an identified endpoint in the checked quest
  records, one lacks coordinates on its quest record, two have conflicting
  coordinates and seven have unresolved or hostile recipient reactions. The
  20 Writs previously excluded on faction evidence remain outside the verified
  quest database.

## Crafting recipes

The [pinned WoW Forever profession extract](https://raw.githubusercontent.com/peligwen/peligaming/2dbb0010e54e1c4436a4691d61315b4ee3faafdb/public/tools/wow-forever/data/professions/professions.json)
contains facts derived from build `1.60.1.70888` (`wowf`). Its
[extraction script](https://github.com/peligwen/peligaming/blob/2dbb0010e54e1c4436a4691d61315b4ee3faafdb/scripts/fetch-wow-forever-professions.mjs)
reads the profession, output, reagent, focus, tool and cooldown tables. MFO
uses 180 item recipes reachable from the verified Writ objectives, including
129 direct outputs. Gordok Ogre Suit has multiple crafting spells in the
extract and remains buy-only. The generator also excludes partial records and
long-cooldown recipes with unaudited availability. The
[Arcanite transmute](https://wow-forever.gg/db/spells/17187-transmute-arcanite/)
can be planned once per shopping estimate when the spell is ready. Borrowed
and estimated Classic trainer thresholds are omitted.

MFO cross-checks each candidate with Forever's
[client API export](https://raw.githubusercontent.com/Atraeau/WoW-Addons/main/types/WowForeverAPI.lua)
for the current character's learned recipe, profession rank, schematic,
requirements and spell cooldown. Exact output and reagent counts must agree.
Unknown or unsupported recipe data leaves the finished purchase available.
Only a verified workstation can be planned as a future visit. Unmet tool and
other restrictions block crafting estimates.

To verify the generated Lua, download the pinned JSON above and run
`python tools/generate_writ_recipes.py professions.json --check`. The generator
checks the snapshot's SHA-256 and uses only recipe facts reachable from the
checked-in Writ objectives.
