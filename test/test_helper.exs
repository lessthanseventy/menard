# :corpus is the hex corpus benchmark: it fetches, and takes minutes (`mise run bench:identity`)
ExUnit.start(exclude: [:corpus])

# the versions the verbs hand out and the formatters' cached deps go to this run's own directory:
# async tests wrote into, and pruned, the cache the live sessions on this machine read
cache = Path.join(System.tmp_dir!(), "menard-test-cache-#{System.pid()}")
Application.put_env(:menard, :cache_dir, cache)
ExUnit.after_suite(fn _ -> File.rm_rf(cache) end)
