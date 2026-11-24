"""Compare normalized quest evidence with candidate facts; no network or runtime writes by default."""
import argparse
import csv
import json
from pathlib import Path

ALLIANCE = 4294967373
HORDE = 8589934770
REWARDS = {"Journeyman": 75, "Expert": 125, "Artisan": 200}
PROFESSIONS = {"Alchemy", "Blacksmithing", "Engineering", "Leatherworking", "Tailoring"}

def faction(mask):
    return {0: "Both", ALLIANCE | HORDE: "Both", ALLIANCE: "Alliance", HORDE: "Horde"}.get(mask)

def verify(c, q):
    if not q:
        return "missing quest evidence"
    if q.get("quest") != int(c["quest"]) or q.get("writ") != int(c["writ"]):
        return "identity mismatch"
    if q.get("items") != {c["item"]: int(c["qty"])}:
        return "objective mismatch"
    if q.get("reputation") != int(c["rep"]) or REWARDS.get(c["tier"]) != int(c["rep"]):
        return "reward mismatch"
    flags = q.get("questFlags")
    if type(flags) is not int or flags < 0 or not flags & 4096 or flags & (32768 | 65536):
        return "daily flag missing or conflicting"
    mask = q.get("requiredRaces")
    if type(mask) is not int or faction(mask) != c["unverifiedFaction"]:
        return "faction missing or conflicting"
    profs = q.get("professions")
    if not isinstance(profs, list) or not profs or any(p not in PROFESSIONS for p in profs) or c["profession"] not in profs:
        return "profession unresolved"
    if not q.get("source") or not q.get("revision") or q.get("redistributionApproved") is not True:
        return "provenance or redistribution approval missing"
    if q.get("otherRestrictions") is not False:
        return "other restrictions unresolved"
    return None

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--candidates", type=Path, default=Path("research/writ-candidates.tsv"))
    p.add_argument("--evidence", type=Path, required=True, help="Locally normalized, reviewed quest evidence JSON keyed by quest ID")
    p.add_argument("--report", type=Path, required=True)
    args = p.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    with args.candidates.open(encoding="utf-8", newline="") as f:
        candidates = list(csv.DictReader(f, delimiter="\t"))
    ids = [c["writ"] for c in candidates]
    if len(ids) != len(set(ids)):
        raise ValueError("duplicate Writ candidate")
    report = {}
    for c in candidates:
        q = evidence.get(c["quest"])
        reason = verify(c, q)
        report[c["writ"]] = {"status": "excluded" if reason else "eligible-for-review", "reason": reason, "candidate": c, "evidence": q if not reason else None}
    for missing in ("264065", "264069", "264124", "264139"):
        report.setdefault(missing, {"status": "excluded", "reason": "missing three-source candidate"})
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True)+"\n", encoding="utf-8")
    print("Reviewed", len(report), "records;", sum(x["status"]=="eligible-for-review" for x in report.values()), "eligible for review")

if __name__ == "__main__":
    main()
