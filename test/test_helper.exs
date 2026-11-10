# :corpus is the hex corpus benchmark: it fetches, and takes minutes (`mise run bench:identity`)
# Half the cores' worth of cases, and four schedulers for every VM a test starts: at the default,
# forty cases each booting a host mix with a scheduler per core pegged the machine and ran single
# tests past their timeout, and finished no sooner (374 s against 397 s, 1 timeout against 0)
ExUnit.start(exclude: [:corpus], max_cases: max(div(System.schedulers_online(), 2), 2))
System.put_env("ERL_FLAGS", String.trim("+S 4 " <> (System.get_env("ERL_FLAGS") || "")))

# the bin tests run the dev build (`--frozen`) and copy it: a checkout that has only run its tests
# (a fresh clone, a worktree) has none
root = Path.expand("..", __DIR__)

if not File.dir?(Path.join(root, "_build/dev/lib/menard/ebin")) do
  {_, 0} = System.cmd("mix", ["compile"], cd: root, env: [{"MIX_ENV", "dev"}], stderr_to_stdout: true)
end

# this VM runs in a Claude Code session: a bin/menard a test starts would find the session's own
# hooks server by this id (Menard.Door) and run the installed plugin's build, not this tree's
System.delete_env("CLAUDE_CODE_SESSION_ID")
# and by its env file, which every SessionStart a test sends would append menard's PATH line to
System.delete_env("CLAUDE_ENV_FILE")

# A verb given no root works where its caller stood, and for this VM that was this checkout: a
# test that lost its root renamed through lib/. Where a test names no directory, an empty one.
nowhere = Path.join(System.tmp_dir!(), "menard-test-nowhere-#{System.pid()}")
File.mkdir_p!(nowhere)
System.put_env("MENARD_CWD", nowhere)
ExUnit.after_suite(fn _ -> File.rm_rf(nowhere) end)

# the versions the verbs hand out and the formatters' cached deps go to this run's own directory:
# async tests wrote into, and pruned, the cache the live sessions on this machine read
cache = Path.join(System.tmp_dir!(), "menard-test-cache-#{System.pid()}")
Application.put_env(:menard, :cache_dir, cache)
ExUnit.after_suite(fn _ -> File.rm_rf(cache) end)

# and its run logs: a session start's sweep reads this run's, not every live session's
logs = Path.join(System.tmp_dir!(), "menard-test-logs-#{System.pid()}")
Application.put_env(:menard, :log_dir, logs)
ExUnit.after_suite(fn _ -> File.rm_rf(logs) end)
