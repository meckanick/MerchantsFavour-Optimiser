import hashlib
import json
from pathlib import Path
import unittest
from unittest.mock import patch

from tools import verify_writs as verifier


class WritVerification(unittest.TestCase):
    def setUp(self):
        self.row = {
            "objectives": [
                {"typeId": 1, "objectId": 264065, "amount": 1},
                {"typeId": 1, "objectId": 9061, "amount": 1},
            ],
            "rewards": {"reputation": [
                {"factionId": 2587, "override": 12500, "tier": 0},
                {"factionId": 2586, "override": 12500, "tier": 0},
            ]},
            "flags": 3149824,
            "raceMask": "ffffffffffffffff",
            "flagsEx": 33281,
            "flagsEx2": 268435456,
            "questType": 2,
            "minLevel": 1,
            "treasurePickerIds": [4818],
        }
        self.candidate = (264065, 94265, 9061, 1, "Expert", 125, None,
                          ("Alchemy", "Engineering"), "test")

    def verify_one(self, *observations):
        with patch.object(verifier, "WRIT_IDS", {264065}):
            report = verifier.audit([self.candidate], {
                str(index): {"94265": row} for index, row in enumerate(observations)
            })
        return report[264065]

    def test_hash_mismatch_is_rejected(self):
        path = Path("source")
        expected = hashlib.sha256(b"exact\n").hexdigest()
        with patch.object(Path, "read_bytes", side_effect=[b"exact\n", b"exact\r\n"]):
            self.assertEqual(verifier.pinned_text(path, expected), "exact\n")
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                verifier.pinned_text(path, expected)

    def test_forever_adapter_rejects_other_products_and_duplicate_keys(self):
        meta = dict(product="wowf", dataset="quests", locale="enUS",
                    schemaVersion=1, clientBuild="test", license="CC BY 4.0")
        text = json.dumps({"meta": meta, "quests": {"94265": self.row}})
        self.assertEqual(verifier.load_quests(text, "test"), {"94265": self.row})
        with self.assertRaisesRegex(ValueError, "metadata"):
            verifier.load_quests(text.replace("wowf", "wow_classic_beta"), "test")
        with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
            verifier.load_quests('{"quests": {}, "quests": {}}', "test")

    def test_explicit_faction_and_daily_flags(self):
        self.assertEqual(self.verify_one(self.row)["status"], "verified")
        for mask in (None, "0", "0000000000000001"):
            with self.subTest(mask=mask):
                self.assertIn("faction missing or conflicting",
                              self.verify_one(dict(self.row, raceMask=mask))["reasons"])
        self.candidate = (*self.candidate[:6], "Horde", *self.candidate[7:])
        self.assertIn("faction missing or conflicting", self.verify_one(self.row)["reasons"])
        self.assertEqual(self.verify_one(dict(self.row, raceMask="00000002000000b2"))["status"],
                         "verified")
        for flags in (None, 0x200000, 0x9000, 0x11000, -1, 4096.0):
            with self.subTest(flags=flags):
                self.assertIn("daily flag missing or conflicting",
                              self.verify_one(dict(self.row, flags=flags))["reasons"])

    def test_conflicting_builds_and_objectives_are_excluded(self):
        changed = dict(self.row, minLevel=20)
        self.assertIn("quest evidence differs across builds",
                      self.verify_one(self.row, changed)["reasons"])
        changed = dict(self.row, objectives=self.row["objectives"][:1] * 2)
        self.assertIn("item objectives differ", self.verify_one(changed)["reasons"])
        changed = dict(self.row, rewards={"reputation": self.row["rewards"]["reputation"][:1]})
        self.assertIn("reward or tier differs", self.verify_one(changed)["reasons"])

    def test_checked_in_audit_matches_generated_lua(self):
        report = json.loads((verifier.RESEARCH / "writ-audit.json").read_bytes())
        rows = {int(writ): row for writ, row in report["writs"].items()}
        self.assertEqual(set(rows), verifier.WRIT_IDS)
        self.assertEqual(sum(row["status"] == "verified" for row in rows.values()), 130)
        for writ in verifier.MISSING:
            self.assertEqual(rows[writ]["status"], "verified")
        self.assertEqual(rows[264065]["professions"], ["Alchemy", "Engineering"])
        self.assertEqual(rows[264144]["professions"], ["Leatherworking", "Tailoring"])
        for row in rows.values():
            self.assertEqual(row["status"] == "verified", not row["reasons"])
            self.assertTrue(set(row["questBuilds"]) <= set(report["sources"]["quests"]))
        lua_path = verifier.ROOT / "MerchantsFavourOptimiser" / "WritData.lua"
        self.assertEqual(verifier.render_lua(rows), lua_path.read_text(encoding="utf-8"))
        self.assertEqual(verifier.render_lua(dict(reversed(list(rows.items())))),
                         verifier.render_lua(rows))


if __name__ == "__main__":
    unittest.main()
