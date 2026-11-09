# :corpus is the hex corpus benchmark: it fetches, and takes minutes (`mise run bench:identity`)
ExUnit.start(exclude: [:corpus])

# this VM runs in a Claude Code session: a bin/menard a test starts would find the session's own
# hooks server by this id (Menard.Door) and run the installed plugin's build, not this tree's
System.delete_env("CLAUDE_CODE_SESSION_ID")
# and by its env file, which every SessionStart a test sends would append menard's PATH line to
System.delete_env("CLAUDE_ENV_FILE")

# the versions the verbs hand out and the formatters' cached deps go to this run's own directory:
# async tests wrote into, and pruned, the cache the live sessions on this machine read
cache = Path.join(System.tmp_dir!(), "menard-test-cache-#{System.pid()}")
Application.put_env(:menard, :cache_dir, cache)
ExUnit.after_suite(fn _ -> File.rm_rf(cache) end)

# and its run logs: a session start's sweep reads this run's, not every live session's
logs = Path.join(System.tmp_dir!(), "menard-test-logs-#{System.pid()}")
Application.put_env(:menard, :log_dir, logs)
ExUnit.after_suite(fn _ -> File.rm_rf(logs) end)
