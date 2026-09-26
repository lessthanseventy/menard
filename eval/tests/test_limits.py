"""The account's usage limit: a step it cuts short is told from the agent failing, waited out, and
redone from where it started; a killed runner resumes a long run from its last checkpoint. No real
session: tests/fake_bin/claude plays recorded streams (tests/fixtures/limits).

    python3 -m unittest discover -s eval/tests
"""

import contextlib
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import unittest.mock
from pathlib import Path
from types import SimpleNamespace

TESTS = Path(__file__).resolve().parent
EVAL = TESTS.parent
sys.path.insert(0, str(EVAL))
import run  # noqa: E402

FIXTURES = TESTS / "fixtures" / "limits"
FAKE_BIN = TESTS / "fake_bin"
# an hour before the recorded limit's resetsAt (1790436000: 2026-09-26 09:20 MDT)
RESETS = 1790436000
NOW = RESETS - 3600
STEPS = [("01", "step one"), ("02", "step two"), ("03", "step three")]


def fixture(name, sid="sess1"):
    return (FIXTURES / name).read_text().replace("SESSION", sid)


def bench(d, ci=False):
    """A suite of one long case (three steps, each checked by its line in work.txt) and one single
    case, a template, and a HOME, TMPDIR and fake-claude state of the test's own."""
    d = Path(d)
    b = SimpleNamespace(d=d, work=d / "work", tpl=d / "template", home=d / "home", tmp=d / "tmp",
                        state=d / "state", out=d / "results" / "r1",
                        long=d / "suite" / "cases" / "long1", one=d / "suite" / "cases" / "one")
    for p in (b.tpl, b.home, b.tmp, b.state):
        p.mkdir(parents=True, exist_ok=True)
    (b.tpl / "README").write_text("fixture\n")
    for n, prompt in STEPS:
        s = b.long / "steps" / n
        s.mkdir(parents=True, exist_ok=True)
        (s / "prompt.md").write_text(prompt + "\n")
        (s / "check.sh").write_text(f"grep -qx '{prompt}' work.txt\n")
    if ci:
        (b.long / "ci").write_text("grep -q 'CI failed' work.txt")
    b.one.mkdir(parents=True, exist_ok=True)
    (b.one / "prompt.md").write_text("the one task\n")
    (b.one / "check.sh").write_text("grep -qx 'the one task' work.txt\n")
    return b


def plan(b, p):
    (b.state / "plan.json").write_text(json.dumps(p))


def observed(b):
    return [json.loads(line) for line in open(b.state / "observed.jsonl")]


def start_of(b, key, attempt=0):
    """The state the fake's call for `key` (its `attempt`th) started from."""
    o = next(o for o in observed(b) if o["key"] == key and o["attempt"] == attempt)
    return {k: o[k] for k in ("sid", "work", "session", "tmp")}


def calls(b, key):
    return [c for c in map(json.loads, open(b.state / "calls.jsonl")) if c["key"] == key]


@contextlib.contextmanager
def patched(b, probe=None):
    """The runner pointed at the bench, with a fixed clock, sleeps recorded, and a probe that says
    the limit has lifted unless the test gives its own."""
    logs, sleeps = [], []
    env = {"HOME": str(b.home), "TMPDIR": str(b.tmp), "FAKE_CLAUDE_STATE": str(b.state),
           "PATH": f"{FAKE_BIN}{os.pathsep}{os.environ['PATH']}"}
    with contextlib.ExitStack() as stack:
        stack.enter_context(unittest.mock.patch.dict(os.environ, env))
        for name, value in {"WORK": b.work, "TEMPLATE": b.tpl, "PLUGINS": b.work / "plugins", "CURRENT": None,
                            "log": lambda line, *_: logs.append(line), "SLEEP": sleeps.append,
                            "CLOCK": lambda: NOW, "PROBE": probe or (lambda: ("ok", None))}.items():
            stack.enter_context(unittest.mock.patch.object(run, name, value))
        yield SimpleNamespace(logs=logs, sleeps=sleeps)


def ws_of(b, case, n=1):
    return b.work / "runs" / b.out.name / f"{case.name}.A.m.{n}"


class TestDetection(unittest.TestCase):
    def setUp(self):
        patcher = unittest.mock.patch.object(run, "CLOCK", lambda: NOW)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_the_accounts_429_is_a_usage_limit_with_its_reset(self):
        hit = run.limit_death(fixture("usage_429.jsonl"))
        self.assertEqual(hit["kind"], "usage")
        self.assertEqual(hit["reset"], RESETS)
        self.assertEqual(hit["session_id"], "sess1")
        self.assertIn("hit your monthly spend limit", hit["reason"])

    def test_the_reset_is_read_from_the_words_when_no_event_carries_it(self):
        text = "\n".join(line for line in fixture("usage_429.jsonl").splitlines() if "rate_limit_event" not in line)
        hit = run.limit_death(text)
        self.assertEqual(hit["kind"], "usage")
        self.assertEqual(hit["reset"], RESETS)

    def test_a_429_on_stderr_with_no_result_is_a_usage_limit_with_a_relative_reset(self):
        hit = run.limit_death(fixture("usage_stderr.txt"))
        self.assertEqual(hit["kind"], "usage")
        self.assertEqual(hit["reset"], NOW + 2 * 3600 + 30 * 60)

    def test_overloaded_is_transient(self):
        hit = run.limit_death(fixture("overloaded_529.jsonl"))
        self.assertEqual(hit["kind"], "transient")
        self.assertIsNone(hit["reset"])

    def test_the_agent_failing_is_not_a_limit(self):
        self.assertIsNone(run.limit_death(fixture("max_turns.jsonl")))
        self.assertIsNone(run.limit_death(fixture("ok.jsonl")))
        # a tool's output and the agent's words about a 429, and a warning event, are not the API's
        self.assertIsNone(run.limit_death(fixture("tool_says_limit.jsonl")))
        # a run killed at its timeout: no result, nothing on stderr
        self.assertIsNone(run.limit_death("\n".join(fixture("ok.jsonl").splitlines()[:3])))

    def test_reset_times(self):
        # 08:20 MDT on 2026-09-26
        self.assertEqual(run.parse_reset("your session limit resets 9:20am (America/Denver)", NOW), RESETS)
        # past it, the next day's
        self.assertEqual(run.parse_reset("resets 9:20am (America/Denver)", RESETS + 60), RESETS + 86400)
        self.assertEqual(run.parse_reset("resets 11pm (America/Denver)", NOW), RESETS + 13 * 3600 + 40 * 60)
        self.assertEqual(run.parse_reset("resets 12am (America/Denver)", NOW), RESETS + 14 * 3600 + 40 * 60)
        self.assertEqual(run.parse_reset("resets Oct 3, 5pm (UTC)", NOW), 1791046800)
        self.assertEqual(run.parse_reset("Try again in 5 minutes.", NOW), NOW + 300)
        self.assertEqual(run.parse_reset("limit resets in 1 hour and 10 minutes", NOW), NOW + 4200)
        self.assertIsNone(run.parse_reset("resets 9:20am (Mars/Olympus)", NOW))
        self.assertIsNone(run.parse_reset("You've hit your monthly spend limit", NOW))


class TestWaiting(unittest.TestCase):
    def wait(self, hit, answers):
        answers = list(answers)
        with tempfile.TemporaryDirectory() as d:
            b = bench(d)
            b.out.mkdir(parents=True)
            with patched(b, probe=lambda: answers.pop(0)) as p:
                waits = run.wait_out(hit, b.out, "02")
            kept = [json.loads(line) for line in open(b.out / "waits.jsonl")]
        return waits, kept, p

    def test_a_stated_reset_is_slept_to_with_its_margin_then_probed(self):
        hit = run.limit_death(fixture("usage_429.jsonl"))
        waits, kept, p = self.wait(hit, [("ok", None)])
        self.assertEqual(p.sleeps, [3600 + run.RESET_MARGIN])
        self.assertEqual(waits, kept)
        self.assertEqual(kept[0]["seconds"], 3720)
        self.assertEqual(kept[0]["step"], "02")
        self.assertIn("resets", kept[0]["why"])
        self.assertIn("hit your monthly spend limit", kept[0]["reason"])
        self.assertTrue(any("waiting until" in line for line in p.logs))
        self.assertTrue(any("redoing the step" in line for line in p.logs))

    def test_no_reset_backs_off_doubling_until_the_probe_goes_through(self):
        hit = {"kind": "usage", "reason": "usage limit", "reset": None, "session_id": "s"}
        still = {"kind": "usage", "reason": "usage limit", "reset": None, "session_id": None}
        _, kept, p = self.wait(hit, [("limited", still), ("limited", still), ("ok", None)])
        self.assertEqual(p.sleeps, [600, 1200, 2400])
        self.assertEqual(len(kept), 3)

    def test_the_back_off_is_capped_and_a_probe_that_learns_the_reset_sleeps_to_it(self):
        hit = {"kind": "usage", "reason": "usage limit", "reset": None, "session_id": "s"}
        still = {"kind": "usage", "reason": "usage limit", "reset": None, "session_id": None}
        told = {"kind": "usage", "reason": "usage limit", "reset": NOW + 100, "session_id": None}
        _, _, p = self.wait(hit, [("limited", still)] * 4 + [("limited", told), ("ok", None)])
        self.assertEqual(p.sleeps, [600, 1200, 2400, 3600, 3600, 100 + run.RESET_MARGIN])

    def test_an_outage_backs_off_short(self):
        _, _, p = self.wait(run.limit_death(fixture("overloaded_529.jsonl")), [("ok", None)])
        self.assertEqual(p.sleeps, [run.TRANSIENT_BACKOFF])

    def test_a_probe_failing_on_something_else_stops_the_round(self):
        hit = {"kind": "usage", "reason": "usage limit", "reset": None, "session_id": "s"}
        with self.assertRaises(run.RoundStop):
            self.wait(hit, [("error", "Please run /login")] * 3)


class TestProbe(unittest.TestCase):
    def test_the_probe_is_one_tiny_call_and_reads_the_limit(self):
        with tempfile.TemporaryDirectory() as d:
            b = bench(d)
            plan(b, {"Reply with the word ok.": ["limit", "ok"]})
            with patched(b):
                status, hit = run.probe()
                self.assertEqual(status, "limited")
                self.assertEqual(hit["reset"], RESETS)
                self.assertEqual(run.probe(), ("ok", None))
            args = calls(b, "Reply with the word ok.")[0]["args"]
            self.assertEqual(args[args.index("--model") + 1], run.PROBE_MODEL)
            self.assertEqual(args[args.index("--max-turns") + 1], "1")
            self.assertIn("--no-session-persistence", args)
            # it keeps no session anywhere
            self.assertFalse((b.home / ".claude").exists())


class TestRedo(unittest.TestCase):
    """A step the limit cut short is redone from the state it started in, as if never interrupted."""

    @classmethod
    def setUpClass(cls):
        cls._dir = tempfile.TemporaryDirectory()
        cls.control = bench(cls._dir.name, ci=True)
        plan(cls.control, {})
        with patched(cls.control):
            cls.control_row = run.run_one(cls.control.long, "A", "m", 1, cls.control.out)

    @classmethod
    def tearDownClass(cls):
        cls._dir.cleanup()

    def setUp(self):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        self.b = bench(d.name, ci=True)

    def test_control_passes_every_step_and_ci(self):
        self.assertTrue(self.control_row["pass"])
        self.assertEqual(self.control_row["steps_passed"], 3)
        self.assertEqual(self.control_row["ci"]["rounds"], 1)
        self.assertEqual(self.control_row["interrupted"], [])

    def test_a_429_mid_step_is_waited_out_and_the_step_redone_from_its_start(self):
        b = self.b
        plan(b, {"step two": ["limit"]})
        with patched(b) as p:
            row = run.run_one(b.long, "A", "m", 1, b.out)
        self.assertTrue(row["pass"])
        # the redo started where the cut attempt did, which is where the uninterrupted run's step started
        self.assertEqual(start_of(b, "step two", 1), start_of(b, "step two", 0))
        self.assertEqual(start_of(b, "step two", 1), start_of(self.control, "step two"))
        # and everything after is as the uninterrupted run's
        self.assertEqual(start_of(b, "step three"), start_of(self.control, "step three"))
        self.assertNotIn("PARTIAL", start_of(b, "step three")["work"])
        # the cut attempt's tokens are its own, not the step's
        self.assertEqual(row["tokens"], self.control_row["tokens"])
        self.assertEqual(row["turns"], self.control_row["turns"])
        [cut] = row["interrupted"]
        self.assertEqual((cut["step"], cut["turns"], cut["kind"]), ("02", 2, "usage"))
        self.assertEqual(cut["tokens"], {"input": 6, "output": 90, "cache_read": 41000, "cache_write": 2100})
        self.assertTrue((b.out / "traces" / cut["trace"]).exists())
        self.assertEqual(p.sleeps, [3600 + run.RESET_MARGIN])
        self.assertEqual([w["step"] for w in row["waits"]], ["02"])
        # nothing of the run is left: workspace, checkpoint, session files
        ws = ws_of(b, b.long)
        self.assertFalse(ws.exists() or run.pre(ws).exists() or run.session_dir(ws).exists())

    def test_a_first_step_cut_short_leaves_no_trace_of_its_session(self):
        b = self.b
        plan(b, {"step one": ["stderr"]})
        with patched(b) as p:
            row = run.run_one(b.long, "A", "m", 1, b.out)
        self.assertTrue(row["pass"])
        redo = start_of(b, "step one", 1)
        # a fresh session, and the dead one's transcript and hook state are gone
        self.assertEqual(redo["sid"], "sess2")
        self.assertEqual(redo, dict(start_of(self.control, "step one"), sid="sess2"))
        self.assertEqual(p.sleeps, [2 * 3600 + 30 * 60 + run.RESET_MARGIN])
        self.assertEqual(start_of(b, "step three")["work"], start_of(self.control, "step three")["work"])

    def test_a_ci_turn_cut_short_is_redone_too(self):
        b = self.b
        plan(b, {"CI failed": ["overload"]})
        with patched(b) as p:
            row = run.run_one(b.long, "A", "m", 1, b.out)
        self.assertTrue(row["ci"]["green"])
        self.assertEqual(row["ci"]["rounds"], 1)
        self.assertEqual(start_of(b, "CI failed", 1), start_of(b, "CI failed", 0))
        self.assertEqual([(c["step"], c["kind"]) for c in row["interrupted"]], [("ci1", "transient")])
        self.assertEqual(p.sleeps, [run.TRANSIENT_BACKOFF])

    def test_a_single_case_is_redone_too(self):
        b = self.b
        plan(b, {"the one task": ["limit"]})
        with patched(b):
            row = run.run_one(b.one, "A", "m", 1, b.out)
        self.assertTrue(row["pass"])
        # a single case keeps no session: the redo is a fresh one, from the same workspace and hook state
        self.assertEqual(start_of(b, "the one task", 1), dict(start_of(b, "the one task", 0), sid="sess2"))
        self.assertEqual(len(row["interrupted"]), 1)
        self.assertFalse(run.pre(ws_of(b, b.one)).exists())

    def test_the_retry_cap_stops_the_round_and_the_same_command_resumes_it(self):
        b = self.b
        plan(b, {"step two": ["limit"] * run.MAX_REDOS})
        with patched(b) as p:
            with self.assertRaises(run.RoundStop) as stopped:
                run.run_one(b.long, "A", "m", 1, b.out)
        self.assertIn("02", str(stopped.exception))
        self.assertEqual(len(p.sleeps), run.MAX_REDOS - 1)
        self.assertFalse((b.out / "runs.jsonl").exists())
        kept = json.loads((run.pre(ws_of(b, b.long)) / "progress.json").read_text())
        self.assertEqual((kept["point"], len(kept["steps"]), len(kept["interrupted"])), ("02", 1, run.MAX_REDOS))
        # the limit lifted, the same command again
        plan(b, {})
        with patched(b):
            row = run.run_one(b.long, "A", "m", 1, b.out)
        self.assertTrue(row["pass"])
        self.assertEqual(len(calls(b, "step one")), 1)
        self.assertEqual([r["point"] for r in row["resumes"]], ["02"])
        self.assertEqual(len(row["interrupted"]), run.MAX_REDOS)
        self.assertEqual(start_of(b, "step two", run.MAX_REDOS), start_of(self.control, "step two"))
        self.assertEqual(start_of(b, "step three"), start_of(self.control, "step three"))
        self.assertEqual(row["tokens"], self.control_row["tokens"])


def child(d):
    """A runner that the kill test kills mid-step."""
    b = bench(d, ci=True)
    with patched(b):
        run.run_one(b.long, "A", "m", 1, b.out)


class TestResume(unittest.TestCase):
    def test_a_runner_killed_mid_step_resumes_the_run_at_that_step(self):
        with tempfile.TemporaryDirectory() as d:
            b = bench(d, ci=True)
            plan(b, {"step two": ["hang"]})
            code = f"import sys; sys.path[:0] = [{str(TESTS)!r}]; import test_limits; test_limits.child({d!r})"
            runner = subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                deadline = time.time() + 60
                while not (b.state / "hanging").exists():
                    self.assertLess(time.time(), deadline, "the runner never reached step two")
                    self.assertIsNone(runner.poll(), "the runner died before step two")
                    time.sleep(0.1)
            finally:
                runner.kill()
                runner.wait()
            fake = int((b.state / "hanging").read_text())
            plan(b, {})
            with patched(b) as p:
                row = run.run_one(b.long, "A", "m", 1, b.out)
            self.assertTrue(row["pass"])
            self.assertEqual(row["steps_passed"], 3)
            self.assertEqual(len(calls(b, "step one")), 1)
            self.assertEqual([r["point"] for r in row["resumes"]], ["02"])
            self.assertTrue(any("resumed at 02" in line for line in p.logs))
            # the killed runner's agent, still working in the workspace, was killed before the restore
            with self.assertRaises(ProcessLookupError):
                for _ in range(20):
                    os.kill(fake, 0)
                    time.sleep(0.05)
                    if open(f"/proc/{fake}/stat").read().split()[2] == "Z":
                        raise ProcessLookupError
            with tempfile.TemporaryDirectory() as c:
                control = bench(c, ci=True)
                plan(control, {})
                with patched(control):
                    run.run_one(control.long, "A", "m", 1, control.out)
                self.assertEqual(start_of(b, "step two", 1), start_of(control, "step two"))
                self.assertEqual(start_of(b, "step three"), start_of(control, "step three"))

    def test_a_run_whose_checkpoint_is_gone_is_redone_from_the_start_and_says_so(self):
        with tempfile.TemporaryDirectory() as d:
            b = bench(d)
            (b.out / "traces").mkdir(parents=True)
            (b.out / "traces" / "long1.A.m.1.01.jsonl").write_text(fixture("ok.jsonl"))
            plan(b, {})
            with patched(b) as p:
                row = run.run_one(b.long, "A", "m", 1, b.out)
            self.assertTrue(row["pass"])
            self.assertTrue(any("redone from the start" in line for line in p.logs))


class TestMain(unittest.TestCase):
    def main(self, d, rows, run_one):
        b = bench(d)
        b.out = Path(d) / "results" / "r1"
        b.out.mkdir(parents=True)
        (b.out / "runs.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows))
        argv = ["run.py", "r1", "--arms", "A", "--models", "m", "--cases", "long1,one", "--suite", str(Path(d) / "suite"), "--seed", "1"]
        with patched(b), contextlib.ExitStack() as stack:
            for name in ("build_template", "build_plugins", "warm_plugins", "cleanup", "remove_workspace"):
                stack.enter_context(unittest.mock.patch.object(run, name, lambda *a, **k: None))
            stack.enter_context(unittest.mock.patch.object(run, "EVAL", Path(d)))
            stack.enter_context(unittest.mock.patch.object(run, "run_one", run_one))
            stack.enter_context(unittest.mock.patch.object(sys, "argv", argv))
            # main installs these; the test process keeps its own
            stack.enter_context(unittest.mock.patch.object(signal, "signal", lambda *a: None))
            run.main()

    def test_finished_runs_are_skipped(self):
        started = []

        def run_one(case, arm, model, n, out_dir):
            started.append(f"{case.name}.{arm}.{model}.{n}")
            return {"pass": True, "clean": True, "turns": 1, "cost_usd": 0.0, "wall_s": 1, "tool_errors": 0, "red_runs": 0, "tools": {}}
        with tempfile.TemporaryDirectory() as d:
            self.main(d, [{"id": "long1.A.m.1"}], run_one)
        self.assertEqual(started, ["one.A.m.1"])

    def test_a_round_stop_exits_cleanly_with_its_reason(self):
        def run_one(case, arm, model, n, out_dir):
            run.CURRENT = (case, "rid", Path("/nonexistent"), {})
            raise run.RoundStop("02: the API's limit ended it 5 times")
        with tempfile.TemporaryDirectory() as d, self.assertRaises(SystemExit) as stopped:
            self.main(d, [], run_one)
        self.assertEqual(stopped.exception.code, 75)


if __name__ == "__main__":
    unittest.main()
