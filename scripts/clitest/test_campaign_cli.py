"""Kampanya testleri: sıralı monitör yer listesi (K1–K9), DESKMAP_* anahtarları ve
kaldırılan `screen-fallback` komutu için deskmap CLI davranışı.

Çalıştır: make cli-test. Uygulama gerekmez; send/fresh_status sahte uygulamayla
değiştirilir, veri klasörü geçici dizindir.
"""
import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

CLI = Path(__file__).resolve().parent.parent / "deskmap"


def load_cli(name="deskmap_campaign"):
    loader = SourceFileLoader(name, str(CLI))
    spec = spec_from_loader(name, loader)
    mod = module_from_spec(spec)
    loader.exec_module(mod)
    return mod


dm = load_cli()


def screen(id, name=None, w=1000, h=800, x=0, desktops=None):
    sc = {"id": id, "name": name or id, "builtin": id == "builtin", "uuid": id.upper() + "-0001",
          "frame": [x, 0, w, h], "visible": [x, 0, w, h]}
    if desktops:
        sc["desktops"] = desktops
    return sc


def win(id, app="Code", screen="external", desktop=1, frame=None, bundle="com.example.code", title="", **extra):
    return {"id": id, "app": app, "title": title, "bundleID": bundle, "screen": screen,
            "desktop": desktop, "frame": frame, "minimized": False, "fullscreen": False, **extra}


def docked_rule(id, places, app="Code", bundle="com.example.code", tokens=(), undocked=None):
    r = {"id": id, "appName": app, "bundleID": bundle, "tokens": list(tokens),
         "docked": dm.parse_place(places[0])}
    if len(places) > 1:
        r["dockedNext"] = [dm.parse_place(p) for p in places[1:]]
    if undocked:
        r["undocked"] = dm.parse_place(undocked)
    return r


def docked_status(screens, windows=(), held=(), rules=()):
    return {"mode": "docked", "profile": "Work", "screens": screens, "windows": list(windows),
            "heldRoles": list(held), "rules": list(rules), "primaryHeight": 800}


class FakeApp(unittest.TestCase):
    """send/fresh_status/DIR/HISTORY sahte; zaman beklemesi yok."""

    status = None

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.sent = []
        tmp = Path(self.tmp.name)
        patches = [
            mock.patch.object(dm, "DIR", tmp),
            mock.patch.object(dm, "HISTORY", tmp / "apply-history"),
            mock.patch.object(dm, "send", lambda command, **q: (self.sent.append((command, q)), self.status)[1]),
            mock.patch.object(dm, "fresh_status", lambda: self.status),
            mock.patch.object(dm.time, "sleep", lambda s: None),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def call(self, fn, **args):
        out, err = io.StringIO(), io.StringIO()
        code = 0
        try:
            with redirect_stdout(out), redirect_stderr(err):
                fn(SimpleNamespace(**args))
        except SystemExit as e:
            code = e.code
        return out.getvalue(), err.getvalue(), code

    def write(self, name, spec):
        path = Path(self.tmp.name) / name
        path.write_text(json.dumps(spec))
        return str(path)

    def write_profile(self, rules, name="Work"):
        doc = {"activeProfileID": "P1", "rules": rules, "profiles": [{"id": "P1", "name": name, "rules": rules}]}
        (Path(self.tmp.name) / "rules.json").write_text(json.dumps(doc))


class DockedListFileErrorTests(unittest.TestCase):

    def plan(self, windows):
        return dm.build_plan({"windows": windows})

    def errors(self, windows):
        err = io.StringIO()
        with redirect_stderr(err), self.assertRaises(SystemExit):
            self.plan(windows)
        return err.getvalue()

    def test_d7_one_element_list_is_a_single_place_without_rest(self):
        r = self.plan([{"app": "Mail", "bundle": "m", "docked": ["external/2"]}])["rules"][0]
        self.assertEqual(r["docked"]["desktop"], 2)
        self.assertNotIn("dockedNext", r)

    def test_d7_empty_docked_list_is_an_error_not_a_silent_rule(self):
        text = self.errors([{"app": "Mail", "bundle": "m", "docked": []}])
        self.assertIn("needs 'docked', 'undocked' or 'place'", text)

    def test_d7_bad_item_in_list_names_window_and_item_problem(self):
        text = self.errors([{"app": "Mail", "bundle": "m", "docked": ["external/1", "external-2/1 left-fifth"]}])
        self.assertIn("windows[1] (Mail)", text)
        self.assertIn("left-fifth", text)

    def test_d7_non_numeric_or_zero_desktop_in_list_is_reported(self):
        for item in ("external-2/x", "external-2/0"):
            with self.subTest(item=item):
                text = self.errors([{"app": "Mail", "bundle": "m", "docked": ["external/1", item]}])
                self.assertIn("windows[1] (Mail)", text)

    def test_d7_same_screen_twice_differing_only_in_case_is_rejected(self):
        text = self.errors([{"app": "Mail", "bundle": "m", "docked": ["External/1", "external/2"]}])
        self.assertIn("one place per screen", text)

    def test_d7_list_under_undocked_is_rejected_even_with_a_docked_value(self):
        text = self.errors([{"app": "Mail", "bundle": "m", "docked": "external/1", "undocked": ["builtin/1", "builtin/2"]}])
        self.assertIn("only 'docked' takes a list", text)

    def test_d7_list_under_place_shortcut_is_rejected(self):
        # `place:` iki modun ortak yeri; liste yalnız `docked:` altında geçerli.
        text = self.errors([{"app": "Mail", "bundle": "m", "place": ["external/1", "external-2/1"]}])
        self.assertIn("only 'docked' takes a list", text)

    def test_d7_place_gives_laptop_and_docked_list_overrides_monitor_mode(self):
        r = self.plan([{"app": "Mail", "bundle": "m", "place": "builtin/3 left-half",
                        "docked": ["external-2/1", "external/2 right-half"]}])["rules"][0]
        self.assertEqual((r["undocked"]["screen"], r["undocked"]["desktop"]), ("builtin", 3))
        self.assertEqual(r["docked"]["screen"], "external-2")
        self.assertEqual(r["dockedNext"][0]["layout"]["x"], 0.5)

    def test_d7_list_accepts_mapping_items_and_text_items_mixed(self):
        r = self.plan([{"app": "Mail", "bundle": "m", "docked": [
            {"screen": "External-2", "desktop": 2, "layout": "top-half"}, "external/1"]}])["rules"][0]
        self.assertEqual((r["docked"]["screen"], r["docked"]["desktop"]), ("external-2", 2))
        self.assertEqual(r["dockedNext"][0]["screen"], "external")

    def test_d7_errors_in_several_windows_are_numbered_together(self):
        text = self.errors([{"app": "A", "bundle": "a", "docked": ["x/1", "x/2"]},
                            {"app": "B", "bundle": "b", "docked": "external/1"},
                            {"app": "C", "bundle": "c", "docked": ["external/0"]}])
        self.assertIn("windows[1] (A)", text)
        self.assertNotIn("windows[2]", text)
        self.assertIn("windows[3] (C)", text)

    def test_d7_three_places_keep_file_order(self):
        r = self.plan([{"app": "Mail", "bundle": "m", "docked": ["external-3/1", "external-2/4", "external/2"]}])["rules"][0]
        self.assertEqual([d["screen"] for d in dm.docked_places(r)], ["external-3", "external-2", "external"])


class ApplyTests(FakeApp):

    def setUp(self):
        super().setUp()
        self.status = docked_status([screen("builtin"), screen("external", x=1000)])
        self.spec = {"windows": [{"app": "Mail", "bundle": "m", "docked": ["external-2/1 left-half", "external/2"]}]}

    def test_d7_dry_run_prints_the_order_and_changes_nothing(self):
        out, _, code = self.call(dm.apply_layout, file=self.write("a.json", self.spec), undo=False,
                                 remove=False, dry_run=True, wait=0)
        self.assertEqual(code, 0)
        self.assertIn("+ Mail: docked external-2/1 [0,0,0.5,1] → external/2", out)
        self.assertIn("(dry run, nothing changed)", out)
        self.assertEqual([c for c, _ in self.sent if c != "status"], [])
        self.assertFalse((Path(self.tmp.name) / "apply-history").exists())

    def test_d7_diff_shows_a_reordered_list_as_changed(self):
        old = [docked_rule("A", ["external/2", "external-2/1"], app="Mail", bundle="m")]
        self.write_profile(old)
        out, _, _ = self.call(dm.apply_layout, file=self.write("a.json", {"windows": [
            {"app": "Mail", "bundle": "m", "docked": ["external-2/1", "external/2"]}]}),
            undo=False, remove=False, dry_run=True, wait=0)
        self.assertIn("~ Mail: docked external/2 → external-2/1, undocked -  →  docked external-2/1 → external/2, undocked -", out)

    def test_d7_applying_the_same_file_twice_reports_unchanged(self):
        path = self.write("a.json", self.spec)
        first = dm.build_plan(dm.load_spec(path))["rules"]
        self.write_profile(first)
        out, _, _ = self.call(dm.apply_layout, file=path, undo=False, remove=False, dry_run=True, wait=0)
        self.assertIn("(rules unchanged)", out)

    def test_d7_real_apply_sends_whole_list_and_undo_restores_previous(self):
        old = [docked_rule("OLD", ["external/1"], app="Mail", bundle="m")]
        self.write_profile(old)
        path = self.write("a.json", self.spec)
        self.call(dm.apply_layout, file=path, undo=False, remove=False, dry_run=False, wait=0)
        sets = [q for c, q in self.sent if c == "profile-set"]
        sent = json.loads(sets[0]["json"])["rules"][0]
        self.assertEqual(sent["id"], "OLD")
        self.assertEqual([d["screen"] for d in sent["dockedNext"]], ["external"])
        self.assertEqual(sent["docked"]["screen"], "external-2")
        self.sent.clear()
        self.call(dm.apply_layout, file=None, undo=True, remove=False, dry_run=False, wait=0)
        restored = json.loads([q for c, q in self.sent if c == "profile-set"][0]["json"])["rules"]
        self.assertEqual(restored, old)
        self.assertNotIn("dockedNext", restored[0])

    def test_d7_remove_matches_by_key_and_drops_the_listed_rule(self):
        keep = docked_rule("K", ["external/1"], app="Notes", bundle="n")
        gone = docked_rule("G", ["external/2", "external-2/1"], app="Mail", bundle="m")
        self.write_profile([keep, gone])
        self.call(dm.apply_layout, file=self.write("a.json", self.spec), undo=False, remove=True,
                  dry_run=False, wait=0)
        rules = json.loads([q for c, q in self.sent if c == "profile-set"][0]["json"])["rules"]
        self.assertEqual([r["id"] for r in rules], ["K"])


class MergeTests(unittest.TestCase):

    def test_d7_file_with_only_undocked_keeps_the_existing_docked_list(self):
        old = [docked_rule("A", ["external-2/1", "external/2"], undocked="builtin/1")]
        new = {"id": "N", "appName": "Code", "bundleID": "com.example.code", "tokens": [],
               "undocked": dm.parse_place("builtin/4")}
        merged, ids = dm.merge_rules(old, [new], replace=False)
        self.assertEqual(ids, ["A"])
        self.assertEqual(len(merged[0]["dockedNext"]), 1)
        self.assertEqual(merged[0]["undocked"]["desktop"], 4)

    def test_d7_list_becomes_single_place_and_loses_the_rest_but_keeps_undocked(self):
        old = [docked_rule("A", ["external-2/1", "external/2"], undocked="builtin/1")]
        new = docked_rule("N", ["external/3"])
        merged, _ = dm.merge_rules(old, [new], replace=False)
        self.assertNotIn("dockedNext", merged[0])
        self.assertEqual(merged[0]["undocked"]["desktop"], 1)

    def test_d7_merge_does_not_share_the_rest_list_with_the_old_rule(self):
        old = [docked_rule("A", ["external-2/1", "external/2"])]
        before = json.dumps(old, sort_keys=True)
        dm.merge_rules(old, [docked_rule("N", ["external-3/1", "external/1"])], replace=False)
        self.assertEqual(json.dumps(old, sort_keys=True), before)


class RulesAndWindowsOutputTests(FakeApp):

    def test_d7_rules_text_shows_arrow_list_and_dash_for_missing_undocked(self):
        self.status = docked_status([screen("builtin")],
                                    rules=[docked_rule("A", ["external-2/1 left-half", "external/2"], app="Mail", bundle="m")])
        out, _, _ = self.call(dm.show_rules, json=False)
        self.assertIn("docked external-2/1 [0,0,0.5,1] → external/2  undocked -", out)

    def test_d7_rules_json_keeps_docked_then_docked_next_order(self):
        rule = docked_rule("A", ["external-2/1", "external/2", "external-3/5"])
        self.status = docked_status([screen("builtin")], rules=[rule])
        out, _, _ = self.call(dm.show_rules, json=True)
        got = json.loads(out)[0]
        self.assertEqual([d["screen"] for d in [got["docked"]] + got["dockedNext"]],
                         ["external-2", "external", "external-3"])

    def test_d7_windows_shows_place_only_when_the_app_reports_it(self):
        self.status = docked_status([screen("builtin"), screen("external")], windows=[
            win(1, app="Mail", place="2"), win(2, app="Notes"), win(3, app="Pinned", place="fallback")])
        out, _, _ = self.call(dm.show_windows, app=None, json=False)
        lines = {l.split()[1]: l for l in out.splitlines()}
        self.assertIn("place=2", lines["Mail"])
        self.assertNotIn("place=", lines["Notes"])
        self.assertIn("place=fallback", lines["Pinned"])


class CheckTests(FakeApp):
    """check gerçek gideceği yere bakar: ilk yer bağlı değilse sıradaki yer."""

    def spec_file(self, places, **extra):
        return self.write("c.json", {"windows": [{"app": "Code", "bundle": "com.example.code", "docked": places}], **extra})

    def run_check(self, places):
        out, _, code = self.call(dm.check_layout, file=self.spec_file(places))
        return out, code

    def test_d7_window_on_the_connected_second_place_counts_as_in_place(self):
        self.status = docked_status([screen("builtin"), screen("external", x=1000)],
                                    windows=[win(1, screen="external", desktop=2)])
        out, code = self.run_check(["external-2/1", "external/2"])
        self.assertEqual(code, 0)
        self.assertIn("✓", out)
        self.assertIn("external/2", out)

    def test_d7_window_on_the_unconnected_first_place_screen_is_not_in_place(self):
        self.status = docked_status([screen("builtin"), screen("external", x=1000)],
                                    windows=[win(1, screen="external", desktop=1)])
        out, code = self.run_check(["external-2/1", "external/2"])
        self.assertEqual(code, 2)
        self.assertIn("want external/2", out)

    def test_d7_first_connected_place_wins_over_a_later_one(self):
        self.status = docked_status([screen("builtin"), screen("external", x=1000), screen("external-2", x=2000)],
                                    windows=[win(1, screen="external", desktop=2)])
        out, code = self.run_check(["external-2/1", "external/2"])
        self.assertEqual(code, 2)
        self.assertIn("want external-2/1", out)

    def test_d7_held_role_is_skipped_for_the_next_place(self):
        self.status = docked_status([screen("builtin"), screen("external", x=1000), screen("external-2", x=2000)],
                                    windows=[win(1, screen="external", desktop=2)], held=["external-2"])
        out, code = self.run_check(["external-2/1", "external/2"])
        self.assertEqual(code, 0, out)

    def test_d7_no_connected_place_reports_left_alone_and_does_not_fail(self):
        self.status = docked_status([screen("builtin")], windows=[win(1, screen="builtin", desktop=1)])
        out, code = self.run_check(["external-2/1", "external/2"])
        self.assertIn("no connected place (left alone)", out)
        self.assertEqual(code, 0)
        self.assertIn("0/0", out)

    def test_d7_desktop_number_is_clamped_to_the_screens_desktop_count(self):
        self.status = docked_status([screen("builtin"), screen("external", x=1000, desktops=3)],
                                    windows=[win(1, screen="external", desktop=3)])
        out, code = self.run_check(["external/9"])
        self.assertEqual(code, 0, out)

    # campaign: desks filtresi ilk yerden kurulur, gerçek gidilen yerden değil
    def test_d7_exposure_looks_at_the_real_destination_not_the_first_listed_place(self):
        # İki pencere de ilk yeri (bağlı olmayan external-2) listeler ama gerçekte
        # external/1'e gider: tam örtülme external/1 üzerinden raporlanmalı.
        self.status = docked_status([screen("builtin"), screen("external", x=1000)], windows=[
            win(1, app="Big", bundle="big", screen="external", desktop=1),
            win(2, app="Small", bundle="small", screen="external", desktop=1)])
        spec = {"windows": [
            {"app": "Big", "bundle": "big", "docked": ["external-2/1 full", "external/1 full"]},
            {"app": "Small", "bundle": "small", "docked": ["external-2/1 center", "external/1 center"]}]}
        out, _, code = self.call(dm.check_layout, file=self.write("c.json", spec))
        self.assertEqual(code, 2)
        self.assertIn("external/1: Small can be completely covered", out)
        self.assertNotIn("external-2/1:", out)

    def test_d7_no_exposure_issue_when_covering_windows_land_on_different_screens(self):
        self.status = docked_status([screen("builtin"), screen("external", x=1000), screen("external-2", x=2000)],
                                    windows=[win(1, app="Big", bundle="big", screen="external-2"),
                                             win(2, app="Small", bundle="small", screen="external")])
        spec = {"windows": [
            {"app": "Big", "bundle": "big", "docked": ["external-2/1 full", "external/1 full"]},
            {"app": "Small", "bundle": "small", "docked": ["external/1 center", "external-2/1 center"]}]}
        out, _, code = self.call(dm.check_layout, file=self.write("c.json", spec))
        self.assertEqual(code, 0, out)
        self.assertNotIn("⚠", out)

    def test_d7_size_check_uses_the_effective_screen_rect(self):
        self.status = docked_status([screen("builtin"), screen("external", x=1000, w=2000, h=800)],
                                    windows=[win(1, screen="external", desktop=1, frame=[1000, 0, 1000, 800])])
        out, code = self.run_check(["external-2/1 left-half", "external/1 left-half"])
        self.assertEqual(code, 0, out)


class DumpTests(FakeApp):

    def setUp(self):
        super().setUp()
        self.rules = [
            docked_rule("A", ["external-2/1 left-half", "external/2", "external-3/5 top-half"], app="Mail", bundle="m",
                        tokens=["inbox"], undocked="builtin/1"),
            docked_rule("B", ["external/3"], app="Notes", bundle="n"),
            docked_rule("C", ["external-2/4", "external/1"], app="Maps", bundle="p"),
        ]
        self.status = docked_status([screen("builtin")], rules=self.rules)

    def dump(self, **args):
        out_path = Path(self.tmp.name) / "dump.yaml"
        base = dict(docked=None, undocked=None, title=None, output=str(out_path))
        out, err, code = self.call(dm.dump_layout, **{**base, **args})
        return out_path, out, err, code

    def test_d7_dump_writes_the_list_in_the_same_order(self):
        path, _, _, _ = self.dump(docked=["external-2"])
        windows = dm.load_spec(str(path))["windows"]
        mail = next(w for w in windows if w["app"] == "Mail")
        self.assertEqual(mail["docked"], ["external-2/1 left-half", "external/2 full", "external-3/5 top-half"])

    def test_d7_single_place_is_written_as_text_not_a_one_element_list(self):
        path, _, _, _ = self.dump(docked=["external/3"])
        notes = next(w for w in dm.load_spec(str(path))["windows"] if w["app"] == "Notes")
        self.assertEqual(notes["docked"], "external/3 full")

    def test_d7_dump_then_build_plan_gives_the_same_places(self):
        path, _, _, _ = self.dump(docked=["external-2", "external/3"])
        rules = dm.build_plan(dm.load_spec(str(path)))["rules"]
        by_app = {r["appName"]: r for r in rules}
        for original in self.rules:
            got = by_app[original["appName"]]
            self.assertEqual(dm.docked_places(got), dm.docked_places(original), original["appName"])
        self.assertEqual(by_app["Mail"]["undocked"], self.rules[0]["undocked"])
        self.assertEqual(by_app["Mail"]["tokens"], ["inbox"])

    def test_d7_round_trip_diff_against_the_source_profile_is_empty(self):
        path, _, _, _ = self.dump(docked=["external-2", "external/3"])
        new = dm.build_plan(dm.load_spec(str(path)))["rules"]
        self.assertEqual(dm.diff_rules(self.rules, new), [])

    def test_d7_docked_filter_matches_a_rule_through_its_later_place(self):
        # external/1 yalnız Maps'in ikinci yeri; Mail ve Notes seçilmemeli.
        path, _, _, _ = self.dump(docked=["external/1"])
        self.assertEqual([w["app"] for w in dm.load_spec(str(path))["windows"]], ["Maps"])

    def test_d7_docked_filter_with_desktop_number_matches_that_entry_only(self):
        path, _, _, _ = self.dump(docked=["external/2"])
        self.assertEqual([w["app"] for w in dm.load_spec(str(path))["windows"]], ["Mail"])

    def test_d7_dump_without_match_fails_with_message(self):
        _, _, err, code = self.dump(docked=["external-9"])
        self.assertEqual(code, 1)
        self.assertIn("no rule matches", err)

    def test_d7_dump_does_not_invent_dockedNext_for_undocked_selection(self):
        path, _, _, _ = self.dump(undocked=["builtin"])
        item = dm.load_spec(str(path))["windows"][0]
        self.assertEqual(item["app"], "Mail")
        self.assertEqual(len(item["docked"]), 3)
        self.assertEqual(item["undocked"], "builtin/1 full")


class EnvAndRemovedCommandTests(unittest.TestCase):

    def test_data_dir_env_moves_all_cli_paths(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(os.environ, {"DESKMAP_DATA_DIR": tmp}):
            mod = load_cli("deskmap_env_dir")
        self.assertEqual(mod.DIR, Path(tmp))
        self.assertEqual(mod.STATUS, Path(tmp) / "status.json")
        self.assertEqual(mod.HISTORY, Path(tmp) / "apply-history")
        self.assertEqual(mod.BACKUPS, Path(tmp) / "Backups")

    def test_data_dir_env_unset_or_empty_falls_back_to_application_support(self):
        for value in (None, ""):
            with self.subTest(value=value):
                env = {k: v for k, v in os.environ.items() if k != "DESKMAP_DATA_DIR"}
                if value is not None:
                    env["DESKMAP_DATA_DIR"] = value
                with mock.patch.dict(os.environ, env, clear=True):
                    mod = load_cli("deskmap_env_default")
                self.assertEqual(mod.DIR, Path.home() / "Library/Application Support/Deskmap")

    def send_with(self, mod, command, **query):
        """send()'i sahte open/pgrep ile koşar; open komutlarını döner."""
        calls = []
        with tempfile.TemporaryDirectory() as tmp, \
                mock.patch.object(subprocess, "run", lambda cmd, **kw: (calls.append(cmd), SimpleNamespace(returncode=0))[1]), \
                mock.patch.object(mod.uuid, "uuid4", lambda: SimpleNamespace(hex="abcdef0123456789")), \
                mock.patch.object(mod, "STATUS", Path(tmp) / "status.json"):
            Path(tmp, "status.json").write_text(json.dumps({"request": "abcdef01"}))
            mod.send(command, **query)
        return calls

    def test_app_env_sends_the_url_to_that_copy(self):
        with mock.patch.dict(os.environ, {"DESKMAP_APP": "/tmp/Other Deskmap.app"}):
            mod = load_cli("deskmap_env_app")
        calls = self.send_with(mod, "profile", name="A B+C")
        open_call = calls[-1]
        self.assertEqual(open_call[:4], ["open", "-g", "-a", "/tmp/Other Deskmap.app"])
        self.assertIn("name=A%20B%2BC", open_call[-1])
        self.assertTrue(open_call[-1].startswith("deskmap://profile?"))

    def test_app_env_unset_does_not_pass_dash_a(self):
        env = {k: v for k, v in os.environ.items() if k != "DESKMAP_APP"}
        with mock.patch.dict(os.environ, env, clear=True):
            mod = load_cli("deskmap_no_app")
        calls = self.send_with(mod, "reapply")
        self.assertNotIn("-a", calls[-1])

    def run_cli(self, *argv):
        env = {**os.environ, "DESKMAP_DATA_DIR": tempfile.gettempdir() + "/deskmap-campaign-none"}
        return subprocess.run([sys.executable, str(CLI), *argv], capture_output=True, text=True, env=env)

    def test_screen_fallback_command_is_gone(self):
        result = self.run_cli("screen-fallback")
        self.assertEqual(result.returncode, 2)
        self.assertIn("invalid choice", result.stderr)
        self.assertFalse(hasattr(dm, "screen_fallback"))

    def test_screen_fallback_is_not_mentioned_in_help_or_source(self):
        help_text = self.run_cli("--help").stdout
        self.assertNotIn("screen-fallback", help_text)
        main_src = CLI.read_text().split("def main")[1]
        self.assertNotIn("screen-fallback", main_src)

    def test_layouts_command_lists_names_without_the_app(self):
        result = self.run_cli("layouts")
        self.assertEqual(result.returncode, 0)
        self.assertIn("left-half", result.stdout)


if __name__ == "__main__":
    unittest.main()
