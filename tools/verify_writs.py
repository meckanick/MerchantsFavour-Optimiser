"""Audit Forever Writs offline using pinned Efficient Games and logistics exports."""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESEARCH = ROOT / "research"
WRIT_IDS = frozenset(range(264011, 264161))
EG_REVISION = "d78a89020881ec338a4a7c1f2a89ee613f68554b"
REWARDS = {"Journeyman": 75, "Expert": 125, "Artisan": 200}
PICKERS = {"Journeyman": 4817, "Expert": 4818, "Artisan": 4819}
SKILLS = {164: "Blacksmithing", 165: "Leatherworking", 171: "Alchemy",
          197: "Tailoring", 202: "Engineering"}
DAILY = 0x1000
WEEKLY_OR_MONTHLY = 0x8000 | 0x10000
RACE_MASKS = {
    "ffffffffffffffff": "Both",
    "00000003000000ff": "Both",
    "000000010000004d": "Alliance",
    "00000002000000b2": "Horde",
}
BUILD_HASHES = {
    "1.60.1.70938": "cc038ecb07f37a74b4bde7e6663950288205487b26d11fdd30687e2811b870f7",
    "1.60.1.70959": "7d462939d968f129ca05346867b668f05d9e9326a0ea57476781058bff60a97f",
    "1.60.1.71037": "a5105a4862409f3b5dac5d997d3bc41ae294b88d0fe9e626561f2ba7067b7770",
}
LOGISTICS_REVISION = "178d06486e6e74c64c034b93392474c22d89fc2e"
LOGISTICS_HASH = "6870679ea44e187765c5936d7983f0cb5820f797799b50c2f1b548d5e9eb61e9"

# Item and quest IDs independently matched in the two comparison indexes, then
# checked against the raw quest objectives. Profession tags include recipe suppliers.
MISSING = {
    264065: (94265, 9061, "Expert", ("Alchemy", "Engineering"),
             "https://www.wowhead.com/forever/guide/professions/engineering-overview-trainer-locations-recipes"),
    264069: (94269, 9060, "Expert", ("Blacksmithing", "Engineering"),
             "https://guide.wow4ever.se/en/items/9060"),
    264124: (94324, 246948, "Artisan", ("Alchemy",),
             "https://www.foreverdb.app/en/forever/items/246948/distilled-firewater"),
    264139: (94339, 18232, "Artisan", ("Engineering",),
             "https://wowforever.ninja/professions/engineering/22704-field-repair-bot-74a/"),
}


def pinned_text(path, expected_hash):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected_hash:
        raise ValueError(f"SHA-256 mismatch: {path}")
    return data.decode("utf-8")


def unique_object(pairs):
    result = dict(pairs)
    if len(result) != len(pairs):
        raise ValueError("duplicate JSON key")
    return result


def load_quests(text, build):
    data = json.loads(text, object_pairs_hook=unique_object)
    metadata = {"product": "wowf", "dataset": "quests", "locale": "enUS",
                "schemaVersion": 1, "clientBuild": build, "license": "CC BY 4.0"}
    if any(data["meta"].get(key) != value for key, value in metadata.items()):
        raise ValueError(f"unexpected EG Link export metadata for {build}")
    return data["quests"]


def quest_facts(row):
    """Project numeric quest facts only. Missing race masks stay unknown."""
    items = {}
    for objective in row.get("objectives", ()):
        item, amount = objective.get("objectId"), objective.get("amount")
        if (objective.get("typeId") != 1 or type(item) is not int or item <= 0
                or type(amount) is not int or amount <= 0 or item in items):
            items = None
            break
        items[item] = amount

    rewards = sorted((r["factionId"], r.get("override"), r.get("tier"))
                     for r in row.get("rewards", {}).get("reputation", []))
    flags = row.get("flags")
    return {
        "items": items,
        "rewards": rewards,
        "raceMask": row.get("raceMask"),
        "flags": flags,
        "flagsEx": row.get("flagsEx"),
        "flagsEx2": row.get("flagsEx2"),
        "type": row.get("questType"),
        "minimumLevel": row.get("minLevel"),
        "timeLimit": row.get("timeLimitSeconds", 0),
        "treasurePickers": row.get("treasurePickerIds"),
    }


def indexed_tsv(text):
    rows = list(csv.DictReader(io.StringIO(text), delimiter="\t"))
    index = {int(row["writ"]): row for row in rows}
    if len(index) != len(rows):
        raise ValueError("duplicate Writ ID")
    return index


def candidate_rows(text, logistics):
    for writ, row in indexed_tsv(text).items():
        quest, item, qty, rep = (int(row[key]) for key in ("quest", "item", "qty", "rep"))
        source = logistics.get(writ)
        professions = ()
        if source and (quest, item, qty, rep) == tuple(
                int(source[key]) for key in ("quest", "item", "count", "rep")):
            skills = [int(source[key]) for key in ("skill", "skill2") if int(source[key])]
            if all(skill in SKILLS for skill in skills):
                professions = tuple(sorted({SKILLS[skill] for skill in skills}))
        if row["profession"] not in professions:
            professions = ()
        yield writ, quest, item, qty, row["tier"], rep, row["unverifiedFaction"], professions, "logistics"

    for writ, (quest, item, tier, professions, source) in MISSING.items():
        yield writ, quest, item, 1, tier, REWARDS[tier], None, professions, source


def audit(candidates, exports):
    report = {}
    quest_ids = set()
    for writ, quest, item, qty, tier, rep, hint, professions, profession_source in sorted(candidates):
        if writ in report or quest in quest_ids:
            raise ValueError("duplicate Writ or quest ID")
        quest_ids.add(quest)
        observations = {build: quest_facts(rows[str(quest)]) for build, rows in exports.items()
                        if str(quest) in rows}
        facts = next(iter(observations.values()), {})
        flags = facts.get("flags")
        faction = RACE_MASKS.get(facts.get("raceMask"))
        daily = (type(flags) is int and flags >= 0 and bool(flags & DAILY)
                 and not flags & WEEKLY_OR_MONTHLY)
        expected_reward = [(faction_id, rep * 100, 0) for faction_id in (2586, 2587)]
        reasons = []
        if not facts:
            reasons.append("missing quest evidence")
        elif any(other != facts for other in observations.values()):
            reasons.append("quest evidence differs across builds")
        if writ == item or facts.get("items") != {writ: 1, item: qty}:
            reasons.append("item objectives differ")
        if (REWARDS.get(tier) != rep or facts.get("rewards") != expected_reward
                or facts.get("treasurePickers") != [PICKERS.get(tier)]):
            reasons.append("reward or tier differs")
        if not daily:
            reasons.append("daily flag missing or conflicting")
        if faction is None or (hint is not None and hint != faction):
            reasons.append("faction missing or conflicting")
        if (facts.get("type"), facts.get("minimumLevel"), facts.get("timeLimit"),
                facts.get("flagsEx"), facts.get("flagsEx2")) != (2, 1, 0, 33281, 268435456):
            reasons.append("unknown quest restriction fields")
        if (not professions or len(professions) != len(set(professions))
                or not set(professions) <= set(SKILLS.values())):
            reasons.append("profession unresolved")
        report[writ] = {
            "quest": quest, "item": item, "qty": qty, "tier": tier, "reputation": rep,
            "faction": faction, "factionHint": hint, "daily": daily,
            "professions": professions, "professionSource": profession_source,
            "questBuilds": list(observations), "questFacts": facts,
            "reasons": reasons, "status": "excluded" if reasons else "verified",
        }
    if set(report) != WRIT_IDS:
        raise ValueError("candidate set must cover all 150 tracked Writ IDs")
    return report


def render_lua(report):
    lines = [
        "-- Generated by tools/verify_writs.py. See WRIT_SOURCES.md and research/writ-audit.json.",
        "-- Adapted factual data from Efficient Games (https://efficient.games), CC BY 4.0.",
        "-- https://creativecommons.org/licenses/by/4.0/",
        "-- WritCalculations adds the Writ itself to the required items.",
        "MFO_WritData = {",
    ]
    for writ, row in sorted(report.items()):
        if row["status"] != "verified":
            continue
        professions = ", ".join(json.dumps(profession) for profession in row["professions"])
        lines.extend([
            "  {",
            f"    id = {writ}, questID = {row['quest']}, sourceKey = \"{writ}\",",
            f"    tier = \"{row['tier']}\", professions = {{{professions}}},",
            f"    reputation = {row['reputation']}, faction = \"{row['faction']}\", daily = true,",
            f"    items = {{{{id = {row['item']}, qty = {row['qty']}}}}},",
            "  },",
        ])
    return "\n".join([*lines, "}", ""])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True, help="Pinned raw input files")
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--lua", type=Path, help="Write the generated Lua table")
    args = parser.parse_args()
    exports = {
        build: load_quests(pinned_text(args.source_dir / f"{build}-quests.enUS.json", digest), build)
        for build, digest in BUILD_HASHES.items()
    }
    logistics = indexed_tsv(pinned_text(args.source_dir / "logistics.tsv", LOGISTICS_HASH))
    candidates = candidate_rows((RESEARCH / "writ-candidates.tsv").read_text(encoding="utf-8"), logistics)
    report = audit(candidates, exports)
    sources = {
        "quests": {
            build: {"url": f"https://raw.githubusercontent.com/JIVESCORP/eg-link-output-wowf/{EG_REVISION}"
                           f"/data/wowf/{build}/quests.enUS.json",
                    "revision": EG_REVISION, "sha256": digest, "license": "CC BY 4.0"}
            for build, digest in BUILD_HASHES.items()
        },
        "logistics": {
            "url": f"https://raw.githubusercontent.com/buildthehomelab/wow-mod-supply-logistics/"
                   f"{LOGISTICS_REVISION}/data/writs.tsv",
            "revision": LOGISTICS_REVISION, "sha256": LOGISTICS_HASH, "license": "CC BY 4.0",
        },
    }
    rows = ",\n".join(
        f'    "{writ}": {json.dumps(row, sort_keys=True)}' for writ, row in sorted(report.items()))
    sources_json = json.dumps(sources, sort_keys=True)
    args.report.write_bytes(f'{{\n  "sources": {sources_json},\n  "writs": {{\n{rows}\n  }}\n}}\n'.encode("utf-8"))
    if args.lua:
        args.lua.write_bytes(render_lua(report).encode("utf-8"))
    verified = sum(row["status"] == "verified" for row in report.values())
    print(f"Reviewed {len(report)} Writs: {verified} verified, {len(report) - verified} excluded")


if __name__ == "__main__":
    main()
