"""Unit tests for the pure parts of the `deskmap` CLI (no running app needed).

Run: make cli-test   (or: python3 -m unittest discover -s scripts/clitest)

Only functions that take their input as arguments are tested here: layout and
placement parsing, layout files → rules, merging, diffs, rule matching and
the coverage check. Commands that talk to the app are covered by
scripts/hooktest/cli.sh, which needs Deskmap running.
"""
import io
import unittest
from contextlib import redirect_stderr
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path

CLI = Path(__file__).resolve().parent.parent / "deskmap"
_loader = SourceFileLoader("deskmap_cli", str(CLI))
_spec = spec_from_loader("deskmap_cli", _loader)
dm = module_from_spec(_spec)
_loader.exec_module(dm)


def window(id, app="Code", title="", bundle="com.example.code", screen="builtin",
           desktop=1, frame=None, **extra):
    return {"id": id, "app": app, "title": title, "bundleID": bundle, "screen": screen,
            "desktop": desktop, "frame": frame, "minimized": False, "fullscreen": False, **extra}


def status(windows, mode="undocked"):
    # One 1000×800 built-in screen at the origin, no menu bar inset.
    return {"mode": mode, "windows": windows, "primaryHeight": 800,
            "screens": [{"id": "builtin", "frame": [0, 0, 1000, 800], "visible": [0, 0, 1000, 800]}]}


def rule(id, app="Code", tokens=(), bundle="com.example.code", undocked=None, docked=None, path=None):
    r = {"id": id, "appName": app, "bundleID": bundle, "tokens": list(tokens)}
    if undocked:
        r["undocked"] = dm.parse_place(undocked)
    if docked:
        r["docked"] = dm.parse_place(docked)
    if path:
        r["path"] = path
    return r


class ParseLayoutTests(unittest.TestCase):

    def test_default_is_full(self):
        self.assertEqual(dm.parse_layout(None), {"x": 0, "y": 0, "w": 1, "h": 1})

    def test_names_are_case_insensitive(self):
        self.assertEqual(dm.parse_layout(" Left-Half "), {"x": 0, "y": 0, "w": 0.5, "h": 1})

    def test_every_named_layout_is_in_range(self):
        for name in dm.NAMED_LAYOUTS:
            with self.subTest(name=name):
                dm.parse_layout(name)

    def test_fractions_text(self):
        self.assertEqual(dm.parse_layout("0.25,0,0.5,1"), {"x": 0.25, "y": 0, "w": 0.5, "h": 1})

    def test_out_of_range_is_rejected(self):
        for text in ("0.6,0,0.5,1", "0,0,0,1", "1,0,0.5,1", "-0.1,0,0.5,1"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                dm.parse_layout(text)

    def test_unknown_name_lists_the_names(self):
        with self.assertRaises(ValueError) as caught:
            dm.parse_layout("left-fifth")
        self.assertIn("left-half", str(caught.exception))

    def test_desktop_only(self):
        self.assertTrue(dm.parse_layout("desktop-only")["desktopOnly"])
        self.assertTrue(dm.parse_layout({"desktopOnly": True, "x": 0.3})["desktopOnly"])

    def test_mapping_keeps_fixed_size(self):
        lay = dm.parse_layout({"x": 0, "y": 0, "w": 1, "h": 1,
                               "fixed": {"anchor": "center", "width": 800, "height": 600}})
        self.assertEqual(lay["fixed"], {"anchor": "center", "width": 800.0, "height": 600.0})

    def test_mapping_needs_all_fields(self):
        with self.assertRaises(ValueError):
            dm.parse_layout({"x": 0, "y": 0, "w": 1})
        with self.assertRaises(ValueError):
            dm.parse_layout({"x": 0, "y": 0, "w": 1, "h": 1, "fixed": {"anchor": "center"}})


class ParsePlaceTests(unittest.TestCase):

    def test_text_with_layout(self):
        self.assertEqual(dm.parse_place("External/2 right-half"),
                         {"screen": "external", "desktop": 2,
                          "layout": {"x": 0.5, "y": 0, "w": 0.5, "h": 1}})

    def test_desktop_defaults_to_one_and_layout_to_full(self):
        place = dm.parse_place("builtin")
        self.assertEqual((place["desktop"], place["layout"]["w"]), (1, 1))

    def test_mapping(self):
        place = dm.parse_place({"screen": "builtin", "desktop": 3, "layout": "top-half"})
        self.assertEqual((place["screen"], place["desktop"], place["layout"]["h"]), ("builtin", 3, 0.5))

    def test_none_means_no_target(self):
        self.assertIsNone(dm.parse_place(None))

    def test_bad_values(self):
        for value in ("", "builtin/0", "builtin/two", {"desktop": 2}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                dm.parse_place(value)


class BuildPlanTests(unittest.TestCase):

    def plan(self, spec):
        return dm.build_plan(spec)

    def test_place_fills_both_modes(self):
        plan = self.plan({"windows": [{"app": "Notes", "bundle": "com.example.notes",
                                       "place": "builtin/2 full"}]})
        r = plan["rules"][0]
        self.assertEqual(r["docked"], r["undocked"])
        self.assertEqual(r["bundleID"], "com.example.notes")

    def test_mode_overrides_place(self):
        plan = self.plan({"windows": [{"app": "Notes", "bundle": "com.example.notes",
                                       "place": "builtin/1", "docked": "external/3 left-half"}]})
        r = plan["rules"][0]
        self.assertEqual((r["docked"]["screen"], r["undocked"]["screen"]), ("external", "builtin"))

    def test_title_string_or_list(self):
        plan = self.plan({"windows": [
            {"app": "Code", "bundle": "b", "title": "Alpha", "place": "builtin"},
            {"app": "Code", "bundle": "b", "title": ["Beta", 2], "place": "builtin"}]})
        self.assertEqual([r["tokens"] for r in plan["rules"]], [["Alpha"], ["Beta", "2"]])

    def test_launch_entries_and_options(self):
        plan = self.plan({"profile": "Work", "replace": 1,
                          "desktops": {"docked": {"External": 4}},
                          "windows": [{"app": "Notes", "bundle": "n", "place": "builtin",
                                       "launch": True}]})
        self.assertEqual(plan["profile"], "Work")
        self.assertTrue(plan["replace"])
        self.assertEqual(plan["desktops"], [("docked", "external", 4)])
        self.assertEqual(plan["launches"][0]["app"], "Notes")

    def test_all_errors_are_reported_together(self):
        stderr = io.StringIO()
        with redirect_stderr(stderr), self.assertRaises(SystemExit):
            self.plan({"windows": [{"place": "builtin"},
                                   {"app": "Notes", "bundle": "n"},
                                   {"app": "Mail", "bundle": "m", "place": "builtin/0"}],
                       "desktops": {"sideways": {"builtin": 2}, "docked": {"external": 40}}})
        text = stderr.getvalue()
        for part in ("windows[1]", "needs 'app'", "windows[2] (Notes)", "windows[3] (Mail)",
                     "unknown mode 'sideways'", "desktops.docked.external"):
            self.assertIn(part, text)


class MergeAndDiffTests(unittest.TestCase):

    def test_update_keeps_id_and_the_other_mode(self):
        old = [rule("OLD", tokens=["Alpha"], undocked="builtin/1", docked="external/1")]
        new = [rule("NEW", tokens=["alpha"], docked="external/2")]
        merged, ids = dm.merge_rules(old, new, replace=False)
        self.assertEqual(ids, ["OLD"])
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0]["docked"]["desktop"], 2)
        self.assertEqual(merged[0]["undocked"]["desktop"], 1)

    def test_other_rules_stay_and_new_ones_are_added(self):
        old = [rule("A", app="Mail", bundle="m", undocked="builtin/1")]
        new = [rule("B", undocked="builtin/2")]
        merged, ids = dm.merge_rules(old, new, replace=False)
        self.assertEqual([r["id"] for r in merged], ["A", "B"])
        self.assertEqual(ids, ["B"])

    def test_replace_drops_the_old_list(self):
        old = [rule("A", app="Mail", bundle="m", undocked="builtin/1")]
        merged, _ = dm.merge_rules(old, [rule("B", undocked="builtin/2")], replace=True)
        self.assertEqual([r["id"] for r in merged], ["B"])

    def test_merge_does_not_mutate_the_old_rules(self):
        old = [rule("A", undocked="builtin/1")]
        dm.merge_rules(old, [rule("B", undocked="builtin/3")], replace=False)
        self.assertEqual(old[0]["undocked"]["desktop"], 1)

    def test_diff_marks_added_changed_and_removed(self):
        old = [rule("A", undocked="builtin/1"), rule("C", app="Mail", bundle="m", undocked="builtin/1")]
        new = [rule("A", undocked="builtin/2"), rule("B", app="Notes", bundle="n", undocked="builtin/1")]
        lines = dm.diff_rules(old, new)
        self.assertEqual([line.split()[0] for line in lines], ["~", "+", "-"])
        self.assertIn("Mail", lines[2])

    def test_unchanged_rule_is_not_listed(self):
        rules = [rule("A", undocked="builtin/1")]
        self.assertEqual(dm.diff_rules(rules, rules), [])


class MatchingTests(unittest.TestCase):

    def test_bundle_wins_over_name(self):
        r = rule("A", app="Other name", bundle="com.example.code")
        self.assertTrue(dm.rule_matches(r, window(1)))
        self.assertFalse(dm.rule_matches(rule("A", bundle="com.example.else"), window(1)))

    def test_name_match_without_bundle_ignores_case(self):
        self.assertTrue(dm.rule_matches(rule("A", app="code", bundle=""), window(1)))

    def test_every_token_must_appear(self):
        r = rule("A", tokens=["alpha", "PAPER"])
        self.assertTrue(dm.rule_matches(r, window(1, title="Alpha — paper.tex")))
        self.assertFalse(dm.rule_matches(r, window(1, title="Alpha — notes")))

    def test_turkish_dotted_capital_i_matches_like_the_app(self):
        # Same lowering as Rule.matches in Swift: "İ" → "i̇", "ı" stays.
        self.assertTrue(dm.rule_matches(rule("A", tokens=["İstanbul"]), window(1, title="istanbul".replace("i", "i̇", 1))))
        self.assertFalse(dm.rule_matches(rule("A", tokens=["ırmak"]), window(1, title="Irmak")))

    def test_document_path_must_be_exact(self):
        r = rule("A", path="/tmp/a.txt")
        self.assertTrue(dm.rule_matches(r, window(1, document="/tmp/a.txt")))
        self.assertFalse(dm.rule_matches(r, window(1, document="/tmp/b.txt")))

    def test_specificity_order_path_then_tokens(self):
        rules = [rule("app"), rule("two", tokens=["a", "b"]), rule("path", path="/x"), rule("one", tokens=["a"])]
        self.assertEqual([r["id"] for r in sorted(rules, key=dm.specificity)], ["path", "two", "one", "app"])


class ReportTests(unittest.TestCase):

    def test_ok_wrong_desktop_and_unused_rule(self):
        rules = [rule("A", tokens=["alpha"], undocked="builtin/2 left-half"),
                 rule("B", undocked="builtin/1"),
                 rule("C", app="Mail", bundle="m", undocked="builtin/1")]
        windows = [window(1, title="alpha", desktop=2, frame=[0, 0, 500, 800]),
                   window(2, title="beta", desktop=3, frame=[0, 0, 1000, 800])]
        ok, total, rows = dm.report(status(windows), rules)
        self.assertEqual((ok, total), (1, 2))
        self.assertTrue(rows[0].lstrip().startswith("✓"))
        self.assertIn("want builtin/1", rows[1])
        self.assertIn("Mail: no open window", rows[2])

    def test_frame_off_by_more_than_40px_is_reported(self):
        rules = [rule("A", undocked="builtin/1 left-half")]
        ok, total, rows = dm.report(status([window(1, frame=[0, 0, 560, 800])]), rules)
        self.assertEqual((ok, total), (0, 1))
        self.assertIn("off by 60px", rows[0])

    def test_temporary_pin_is_not_counted(self):
        rules = [rule("A", undocked="builtin/1")]
        w = window(1, desktop=3, pinned={"screen": "builtin", "desktop": 3})
        ok, total, rows = dm.report(status([w]), rules)
        self.assertEqual((ok, total), (0, 0))
        self.assertIn("temporary pin wins", rows[0])

    def test_rules_of_the_other_mode_are_ignored(self):
        rules = [rule("A", docked="external/1")]
        self.assertEqual(dm.report(status([window(1)]), rules), (0, 0, []))

    def test_target_rect_uses_top_left_origin(self):
        st = status([])
        st["screens"][0]["visible"] = [0, 0, 1000, 775]   # 25 px menu bar on top
        self.assertEqual(dm.target_rect(st, "builtin", dm.parse_layout("bottom-half")),
                         [0, 25 + 387.5, 1000, 387.5])
        self.assertIsNone(dm.target_rect(st, "builtin", dm.parse_layout("desktop-only")))
        self.assertIsNone(dm.target_rect(st, "external", dm.parse_layout("full")))


class FreeDurationTests(unittest.TestCase):

    def test_minutes_hours_and_words(self):
        self.assertEqual(dm.free_duration("15m"), 15)
        self.assertEqual(dm.free_duration("30"), 30)
        self.assertEqual(dm.free_duration("10 min"), 10)
        self.assertEqual(dm.free_duration("2H"), 120)
        self.assertEqual(dm.free_duration(" Lock "), "lock")
        self.assertEqual(dm.free_duration("end"), "end")

    def test_bad_durations(self):
        for text in ("0m", "-5", "1.5h", "soon", "15s", ""):
            with self.subTest(text=text), self.assertRaises(ValueError):
                dm.free_duration(text)


class StatusTextTests(unittest.TestCase):

    def test_desktop_moves_line_only_when_off(self):
        self.assertIsNone(dm.desktop_moves_text("on"))
        self.assertIsNone(dm.desktop_moves_text(None))   # older app
        for state in ("held", "reduced", "unavailable"):
            self.assertIn("desktop moves OFF", dm.desktop_moves_text(state))


class ExposureTests(unittest.TestCase):

    def test_nested_windows_can_both_be_covered(self):
        # Either stacking order hides one of them completely.
        rules = [rule("A", app="Big", bundle="big", undocked="builtin/1 full"),
                 rule("B", app="Small", bundle="small", undocked="builtin/1 center")]
        ws = [window(1, app="Big", bundle="big"), window(2, app="Small", bundle="small")]
        issues = dm.exposure_issues(status(ws), rules)
        self.assertEqual(issues, ["builtin/1: Big can be completely covered",
                                  "builtin/1: Small can be completely covered"])

    def test_side_by_side_windows_are_fine(self):
        rules = [rule("A", app="Left", bundle="l", undocked="builtin/1 left-half"),
                 rule("B", app="Right", bundle="r", undocked="builtin/1 right-half")]
        ws = [window(1, app="Left", bundle="l"), window(2, app="Right", bundle="r")]
        self.assertEqual(dm.exposure_issues(status(ws), rules), [])

    def test_different_desktops_do_not_cover_each_other(self):
        rules = [rule("A", app="Big", bundle="big", undocked="builtin/1 full"),
                 rule("B", app="Small", bundle="small", undocked="builtin/2 center")]
        ws = [window(1, app="Big", bundle="big"), window(2, app="Small", bundle="small")]
        self.assertEqual(dm.exposure_issues(status(ws), rules), [])


class ScreenRoleTest(unittest.TestCase):
    """`screen-role` and `screens` with a fake app (send/fresh_status replaced)."""

    STATUS = {"screens": [
        {"id": "builtin", "name": "Built-in", "builtin": True, "uuid": "B0000000",
         "frame": [0, 0, 1710, 1112]},
        {"id": "external", "name": "Pebble", "builtin": False, "uuid": "PEBBLE-0002",
         "frame": [1710, 0, 1920, 1080]}],
        "displayRoles": {"remembered": {"external": ["DELL-0001"]}},
        "heldRoles": ["external"]}

    def setUp(self):
        self.sent = []
        self._send, self._fresh = dm.send, dm.fresh_status
        dm.send = lambda command, **q: (self.sent.append(command), self.STATUS)[1]
        dm.fresh_status = lambda: self.STATUS

    def tearDown(self):
        dm.send, dm.fresh_status = self._send, self._fresh

    def run_cli(self, fn, **args):
        out = io.StringIO()
        from contextlib import redirect_stdout
        with redirect_stdout(out):
            fn(type("Args", (), {"json": False, "display": None, "role": None,
                                 "forget": False, **args})())
        return out.getvalue()

    def test_forget_alone_forgets_every_monitor(self):
        self.run_cli(dm.screen_role, forget=True)
        self.assertEqual(self.sent, ["screen-role-forget"])

    def test_forget_one_monitor_by_name(self):
        out = self.run_cli(dm.screen_role, display="pebble", forget=True)
        self.assertEqual(self.sent, ["screen-role-forget/PEBBLE-0002"])
        self.assertIn("waits for a choice", out)

    def test_confirming_a_held_monitor_sends_its_role(self):
        self.run_cli(dm.screen_role, display="pebble", role="2")
        self.assertEqual(self.sent, ["screen-role/PEBBLE-0002/external-2"])

    def test_held_role_is_shown_with_how_to_confirm(self):
        out = self.run_cli(dm.show_screens)
        self.assertIn("role on hold", out)
        self.assertIn("deskmap screen-role PEBBLE-00 external", out)


if __name__ == "__main__":
    unittest.main()
