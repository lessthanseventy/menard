"""The trace metrics, on traces built here and on the real ones in results/ when they are on disk.

    python3 -m unittest discover -s eval/tests
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

EVAL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVAL))
import run  # noqa: E402

WS = Path("/ws")
# the traces are not in git: point this at a checkout's results/ that has them
RESULTS = Path(os.environ.get("MENARD_EVAL_RESULTS", EVAL / "results"))


class Trace:
    """A stream-json trace of tool calls: `call(name, input, result, error)` in order."""

    def __init__(self):
        self.lines, self.n = [], 0

    def call(self, name, inp, result="ok", error=False, usage=None):
        self.n += 1
        tid = f"t{self.n}"
        usage = usage or {"input_tokens": 10, "cache_read_input_tokens": 100, "cache_creation_input_tokens": 0}
        self.lines.append({"type": "assistant", "message": {"id": f"m{self.n}", "usage": usage,
                                                            "content": [{"type": "tool_use", "id": tid, "name": name, "input": inp}]}})
        self.lines.append({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": tid,
                                                                    "content": result, "is_error": error}]}})
        return self

    def hook(self, name, output):
        self.lines.append({"type": "system", "subtype": "hook_response", "hook_name": name, "output": output, "stderr": ""})
        return self

    def write(self, path):
        self.lines.append({"type": "result", "subtype": "success", "num_turns": self.n, "session_id": "s1",
                           "usage": {"input_tokens": 1, "output_tokens": 2, "cache_read_input_tokens": 3, "cache_creation_input_tokens": 4}})
        path.write_text("".join(json.dumps(l) + "\n" for l in self.lines))
        return path


def bash(cmd):
    return "Bash", {"command": cmd}


def metrics(trace):
    with tempfile.TemporaryDirectory() as d:
        return run.trace_metrics(trace.write(Path(d) / "t.jsonl"), WS)


def habits(*traces):
    with tempfile.TemporaryDirectory() as d:
        return run.trace_habits([t.write(Path(d) / f"{i}.jsonl") for i, t in enumerate(traces)])


class TestRuns(unittest.TestCase):
    def test_an_edit_and_a_test_in_one_command_is_a_run_with_an_edit_before_it(self):
        t = Trace()
        for _ in range(2):
            t.call(*bash("python3 - <<'EOF'\np='lib/a.ex'\ns=open(p).read()\nopen(p,'w').write(s)\nEOF\nbin/menard run test test/a_test.exs"))
        h = habits(t)
        self.assertEqual((h["test_runs"], h["reruns"]), (2, 0))

    def test_two_runs_with_no_edit_between_is_a_rerun(self):
        h = habits(Trace().call(*bash("mix test")).call(*bash("mix test test/a_test.exs")))
        self.assertEqual((h["test_runs"], h["reruns"]), (2, 1))

    def test_an_edit_tool_call_between_two_runs_is_not_a_rerun(self):
        h = habits(Trace().call(*bash("mix test")).call("Edit", {"file_path": "/ws/lib/a.ex"}).call(*bash("mix test")))
        self.assertEqual((h["test_runs"], h["reruns"]), (2, 0))

    def test_a_heredoc_that_mentions_the_tests_is_not_a_run(self):
        h = habits(Trace().call(*bash("git commit -q -F - <<'EOF'\nfix: ran mix test and mise run check\nEOF")))
        self.assertEqual(h["test_runs"], 0)

    def test_every_door_to_the_tests_counts(self):
        for cmd in ["mise run menard -- run test --in server", "mise run menard -- run check --in console",
                    "/tmp/x/plugins/all/bin/menard run test test/a_test.exs", "mix -C server test",
                    "../scripts/cap.sh mix test 2>&1 | grep summary", "mise run server:test", "mise run check",
                    "cd server && mix precommit", "mix menard.run test"]:
            with self.subTest(cmd=cmd):
                self.assertEqual(habits(Trace().call(*bash(cmd)))["test_runs"], 1)
        h = habits(Trace().call("mcp__plugin_manos_menard__run", {"verb": "test", "file": "test/a_test.exs"}))
        self.assertEqual(h["test_runs"], 1)

    def test_a_run_with_no_edit_since_the_step_before_is_a_rerun_across_steps(self):
        h = habits(Trace().call(*bash("mix test")), Trace().call(*bash("mix test")))
        self.assertEqual((h["test_runs"], h["reruns"]), (2, 1))


class TestGate(unittest.TestCase):
    def test_reading_credo_config_or_grepping_for_precommit_is_not_the_gate(self):
        t = Trace().call("Read", {"file_path": "/ws/.credo.exs"}).call("Grep", {"pattern": "precommit|credo"}) \
            .call(*bash("cat .credo.exs; grep -rn precommit mix.exs"))
        self.assertEqual(habits(t)["ran_gate"], 0)

    def test_every_door_to_the_gate_counts(self):
        for cmd in ["mix credo --strict", "cd server && mix precommit", "mise run check", "mise run server:check",
                    "bin/menard run check", "mise run menard -- run check --in server", "mix -C console credo"]:
            with self.subTest(cmd=cmd):
                self.assertEqual(habits(Trace().call(*bash(cmd)))["ran_gate"], 1)
        self.assertEqual(habits(Trace().call("mcp__plugin_manos_menard__run", {"verb": "check"}))["ran_gate"], 1)
        self.assertEqual(habits(Trace().call("mcp__plugin_manos_menard__run", {"verb": "test"}))["ran_gate"], 0)


class TestFailures(unittest.TestCase):
    def test_a_red_test_run_is_not_a_tool_error(self):
        m = metrics(Trace().call(*bash("bin/menard run test"), result='{"ok":false,"failures":[]}', error=True)
                    .call(*bash("mix test"), result="3 tests, 1 failure", error=True))
        self.assertEqual((m["red_runs"], m["tool_errors"]), (2, 0))

    def test_a_red_run_piped_to_green_is_still_red(self):
        for out in ["summary: 10 tests, 2 failures\nexit=2", "  summary: Failed: 1 test\n  ✗ exit 2", '{"exit":2,"ok":false}']:
            with self.subTest(out=out):
                m = metrics(Trace().call(*bash("../scripts/cap.sh mix test | grep -E 'summary|exit'"), result=out))
                self.assertEqual((m["red_runs"], m["tool_errors"]), (1, 0))
        for out in ["summary: 10 tests, 0 failures", "  summary: Result: 12 passed\n  ✓ exit 0", '{"ok":true,"failed":0}']:
            with self.subTest(out=out):
                m = metrics(Trace().call(*bash("../scripts/cap.sh mix test | grep summary"), result=out))
                self.assertEqual(m["red_runs"], 0)

    def test_a_failed_edit_is_a_tool_error_and_its_repeat_a_retry(self):
        m = metrics(Trace().call("Edit", {"file_path": "/ws/lib/a.ex"}, result="old_string not found", error=True)
                    .call("Edit", {"file_path": "/ws/lib/a.ex"}))
        self.assertEqual((m["tool_errors"], m["red_runs"], m["retries"]), (1, 0, 1))

    def test_a_test_after_a_red_test_is_a_rerun_not_a_retry(self):
        m = metrics(Trace().call(*bash("mix test"), result="1 failure", error=True).call(*bash("mix test")))
        self.assertEqual((m["retries"], m["red_runs"]), (0, 1))


class TestRereads(unittest.TestCase):
    def test_a_shell_edit_counts_as_an_edit(self):
        t = Trace().call(*bash("python3 - <<'E'\np='lib/server/a.ex'\ns=open(p).read()\nopen(p,'w').write(s)\nE")) \
            .call("Read", {"file_path": "/ws/server/lib/server/a.ex"}) \
            .call(*bash("cat lib/server/a.ex"))
        self.assertEqual(metrics(t)["rereads"], 2)

    def test_sed_in_place_counts_and_a_read_of_another_file_does_not(self):
        t = Trace().call(*bash("sed -i 's/a/b/' lib/server/a.ex")).call("Read", {"file_path": "/ws/server/lib/server/b.ex"})
        self.assertEqual(metrics(t)["rereads"], 0)
        t.call("Read", {"file_path": "/ws/server/lib/server/a.ex"})
        self.assertEqual(metrics(t)["rereads"], 1)

    def test_a_shell_read_is_not_an_edit(self):
        t = Trace().call(*bash("sed -n 1,20p lib/a.ex; cat lib/b.ex | head")).call("Read", {"file_path": "/ws/lib/a.ex"})
        self.assertEqual(metrics(t)["rereads"], 0)
        self.assertFalse(run.shell_edit("sed -n 1,20p lib/a.ex; cat lib/b.ex | head; mise run check >$TMPDIR/c.log 2>&1"))
        self.assertFalse(run.shell_edit("mix run -e 'IO.inspect(fn -> x end)' 2>/dev/null"))


class TestFormats(unittest.TestCase):
    def test_hand_formats(self):
        for cmd, n in [("mix -C server format 2>/dev/null; (cd server && mix format --check-formatted)", 1),
                       ("cd server && mix format", 1), ("mix format --check-formatted", 0), ("mise exec -- mix format", 1)]:
            with self.subTest(cmd=cmd):
                self.assertEqual(habits(Trace().call(*bash(cmd)))["hand_formats"], n)


class TestTraces(unittest.TestCase):
    def test_a_long_runs_traces_are_its_own_steps_only(self):
        with tempfile.TemporaryDirectory() as d:
            traces = Path(d) / "traces"
            traces.mkdir()
            for n in ["c.A.m.1.01", "c.A.m.1.02", "c.A.m.1.ci1", "c.A.m.10.01", "c.A.m.11"]:
                (traces / f"{n}.jsonl").touch()
            self.assertEqual([t.name for t in run.traces_of(Path(d), "c.A.m.1")],
                             ["c.A.m.1.01.jsonl", "c.A.m.1.02.jsonl", "c.A.m.1.ci1.jsonl"])
            self.assertEqual([t.name for t in run.traces_of(Path(d), "c.A.m.11")], ["c.A.m.11.jsonl"])


@unittest.skipUnless((RESULTS / "focus2" / "traces").exists(), "focus2's traces are not on disk")
class TestFocus2(unittest.TestCase):
    """focus2 recounted (docs/review/2026-09-26-fable.md, items 15 and 16). The rows said all 8 runs / 4
    reruns and 2 failed calls, A 5 / 1 and 0: a command that edits and then runs the tests counted as a
    rerun, and one with a heredoc in it not at all (A's usual form, 6 of its 11 runs). The failed calls
    were red `bin/menard run`s, which exit non-zero where A's piped runs do not; read off the result
    text, all had 3 red runs (one behind an exit 0) and A 4 (one a `mix test` from the wrong directory)."""

    def counts(self, arm):
        d = RESULTS / "focus2"
        rid = f"focus.{arm}.claude-sonnet-5.1"
        h = run.trace_habits(run.traces_of(d, rid))
        steps = [run.trace_metrics(t, Path(f"/tmp/menard-eval-tlon/runs/focus2/{rid}")) for t in run.traces_of(d, rid)]
        return h, {k: sum(s[k] for s in steps) for k in ("tool_errors", "red_runs", "retries", "rereads")}

    def test_all(self):
        h, m = self.counts("all")
        self.assertEqual((h["test_runs"], h["reruns"], h["ran_gate"], h["hand_formats"]), (8, 0, 6, 0))
        self.assertEqual((m["tool_errors"], m["red_runs"], m["retries"]), (0, 3, 0))

    def test_A(self):
        h, m = self.counts("A")
        self.assertEqual((h["test_runs"], h["reruns"], h["ran_gate"], h["hand_formats"]), (11, 2, 3, 5))
        self.assertEqual((m["tool_errors"], m["red_runs"], m["retries"]), (0, 4, 0))


if __name__ == "__main__":
    unittest.main()
