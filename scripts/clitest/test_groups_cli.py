"""Unit tests for the pin group parts of the `deskmap` CLI (no running app needed).

Run: make cli-test
"""
import io
import unittest
from contextlib import redirect_stderr
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path

CLI = Path(__file__).resolve().parent.parent / "deskmap"
_loader = SourceFileLoader("deskmap_cli_groups", str(CLI))
_spec = spec_from_loader("deskmap_cli_groups", _loader)
dm = module_from_spec(_spec)
_loader.exec_module(dm)


def rule(id, app="Preview", tokens=(), group=None, docked=None, undocked=None):
    r = {"id": id, "appName": app, "bundleID": "com.apple.Preview", "tokens": list(tokens)}
    if group:
        r["groupID"] = group
    if docked:
        r["docked"] = {"screen": docked[0], "desktop": docked[1], "layout": {"x": 0, "y": 0, "w": 1, "h": 1}}
    if undocked:
        r["undocked"] = {"screen": undocked[0], "desktop": undocked[1],
                         "layout": {"x": 0, "y": 0, "w": 1, "h": 1}}
    return r


def status():
    return {
        "mode": "docked",
        "desktopNames": {"builtin": {"3": "Nova Projesi"}},
        "rules": [rule("r1", tokens=["Orion_report_v3"], group="g1", docked=("builtin", 3)),
                  rule("r2", tokens=["Vega_notes"], group="g1", undocked=("builtin", 4)),
                  rule("r3", tokens=["Expo_template"], docked=("builtin", 3))],
        "pinGroups": [{"id": "g1", "name": "Nova drafts", "rules": ["r1", "r2"]},
                      {"id": "g2", "name": "Nova", "rules": []},
                      {"id": "g3", "name": "Orion", "rules": []},
                      {"id": "g4", "name": "orion", "rules": []}],
    }


class ResolveGroupTests(unittest.TestCase):

    def dies(self, fn, *args):
        err = io.StringIO()
        with redirect_stderr(err), self.assertRaises(SystemExit):
            fn(*args)
        return err.getvalue()

    def test_id_name_and_part(self):
        s = status()
        self.assertEqual(dm.resolve_group(s, "g3"), "g3")
        self.assertEqual(dm.resolve_group(s, "NOVA DRAFTS"), "g1")
        # Tam ad parçadan önce gelir: "nova" tek tam eşleşme.
        self.assertEqual(dm.resolve_group(s, "nova"), "g2")
        self.assertEqual(dm.resolve_group(s, "drafts"), "g1")

    def test_ambiguous_lists_candidates(self):
        message = self.dies(dm.resolve_group, status(), "Orion")
        self.assertIn("matches 2 pin groups", message)
        self.assertIn("g3", message)
        self.assertIn("g4", message)

    def test_missing(self):
        message = self.dies(dm.resolve_group, status(), "Lumen")
        self.assertIn("no pin group 'Lumen'", message)
        # Eski uygulama alanı yazmıyor: grup yok.
        self.assertIn("no pin group", self.dies(dm.resolve_group, {"rules": []}, "x"))


class GroupLinesTests(unittest.TestCase):

    def test_members_and_empty(self):
        lines = dm.group_lines(status())
        self.assertEqual(lines[0], "Nova drafts (2 pins)  g1")
        self.assertEqual(lines[1], "    Preview Orion_report_v3  builtin/3 (Nova Projesi)")
        self.assertEqual(lines[2], "    Preview Vega_notes  - (no docked place)")
        self.assertEqual(lines[3], "Nova (empty)  g2")

    def test_old_status_without_groups(self):
        self.assertEqual(dm.group_lines({"rules": []}), [])

    def test_member_shows_where_it_actually_goes(self):
        # İlk yer (external) bağlı değil; sıralı listedeki builtin/2 kazanır.
        s = status()
        s["screens"] = [{"id": "builtin", "desktops": 4}]
        s["rules"][0]["docked"]["screen"] = "external"
        s["rules"][0]["dockedNext"] = [{"screen": "builtin", "desktop": 2,
                                         "layout": {"x": 0, "y": 0, "w": 1, "h": 1}}]
        self.assertEqual(dm.group_lines(s)[1], "    Preview Orion_report_v3  builtin/2")
        # Gidecek yer yoksa ilk yer "(not connected)" ile.
        del s["rules"][0]["dockedNext"]
        self.assertEqual(dm.group_lines(s)[1], "    Preview Orion_report_v3  external/3 (not connected)")


class GroupCommandTests(unittest.TestCase):

    def run_cmd(self, fn, args, after=None):
        sent = []
        dm.fresh_status = lambda: status()
        dm.send = lambda command, **q: sent.append((command, q)) or (after or status())
        err = io.StringIO()
        try:
            with redirect_stderr(err):
                fn(*args)
            code = 0
        except SystemExit as e:
            code = e.code
        return code, err.getvalue(), sent

    def setUp(self):
        self._saved = (dm.fresh_status, dm.send)

    def tearDown(self):
        dm.fresh_status, dm.send = self._saved

    def ns(self, **kw):
        import argparse
        return argparse.Namespace(**kw)

    def test_remove_refuses_a_non_member(self):
        code, err, sent = self.run_cmd(dm.group_members, (self.ns(group="g1", rules=["r3"]), "remove"))
        self.assertEqual(code, 1)
        self.assertIn("not in this pin group: r3", err)
        self.assertEqual(sent, [])
        code, _, sent = self.run_cmd(dm.group_members, (self.ns(group="g1", rules=["r1"]), "remove"))
        self.assertEqual(code, 0)
        self.assertEqual(sent[0][1], {"remove": "r1"})

    def test_rename_checks_the_result(self):
        renamed = status()
        renamed["pinGroups"][0]["name"] = "Drafts"
        code, _, _ = self.run_cmd(dm.group_rename, (self.ns(group="g1", name="Drafts"),), after=renamed)
        self.assertEqual(code, 0)
        code, err, _ = self.run_cmd(dm.group_rename, (self.ns(group="g1", name="Drafts"),))
        self.assertEqual(code, 1)
        self.assertIn("was not renamed", err)


class RuleLinesTests(unittest.TestCase):

    def test_group_suffix(self):
        lines = dm.rule_lines(status())
        self.assertIn("[group: Nova drafts]", lines[0])
        self.assertNotIn("[group:", lines[2])

    def test_unknown_group_is_not_shown(self):
        s = status()
        s["rules"][2]["groupID"] = "gone"
        self.assertNotIn("[group:", dm.rule_lines(s)[2])
        del s["pinGroups"]
        self.assertNotIn("[group:", dm.rule_lines(s)[0])


class GroupParserTests(unittest.TestCase):

    def test_subcommands(self):
        p = dm.build_parser()
        a = p.parse_args(["group", "create", "Nova drafts", "r1", "r2"])
        self.assertEqual((a.gcmd, a.name, a.rules), ("create", "Nova drafts", ["r1", "r2"]))
        a = p.parse_args(["group", "list", "--json"])
        self.assertTrue(a.json)
        a = p.parse_args(["group", "rename", "g1", "Drafts"])
        self.assertEqual((a.group, a.name), ("g1", "Drafts"))
        a = p.parse_args(["group", "rm", "g1"])
        self.assertEqual(a.group, "g1")
        for name in ("add", "remove"):
            a = p.parse_args(["group", name, "g1", "r3"])
            self.assertEqual((a.gcmd, a.group, a.rules), (name, "g1", ["r3"]))
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            p.parse_args(["group", "create", "OnlyName"])


class MergeRulesGroupTests(unittest.TestCase):

    def test_replace_carries_the_old_group(self):
        old = [rule("old1", tokens=["a"], group="g1", docked=("builtin", 1)),
               rule("old2", tokens=["b"], docked=("builtin", 1))]
        new = [rule("new1", tokens=["a"], docked=("builtin", 2)),
               rule("new2", tokens=["b"], group="g9", docked=("builtin", 2)),
               rule("new3", tokens=["c"], docked=("builtin", 2))]
        merged, ids = dm.merge_rules(old, new, replace=True)
        self.assertEqual(ids, ["new1", "new2", "new3"])
        self.assertEqual(merged[0]["groupID"], "g1")
        self.assertEqual(merged[1]["groupID"], "g9")
        self.assertNotIn("groupID", merged[2])
        # Girdi değişmez.
        self.assertNotIn("groupID", new[0])

    def test_merge_keeps_the_old_group(self):
        old = [rule("old1", tokens=["a"], group="g1", docked=("builtin", 1))]
        new = [rule("new1", tokens=["a"], docked=("builtin", 2))]
        merged, ids = dm.merge_rules(old, new, replace=False)
        self.assertEqual(ids, ["old1"])
        self.assertEqual(merged[0]["groupID"], "g1")
        self.assertEqual(merged[0]["docked"]["desktop"], 2)


if __name__ == "__main__":
    unittest.main()
