# The template's language server, warmed once: its engine built and the project indexed into
# `.expert/`, which every run's copy of the template starts with, as a project that has been worked
# in does. Cold, expert answered in 68s on the fixture; from a copied warm `.expert/`, 32s.
#
#     mix run eval/warm_expert.exs TEMPLATE
[dir] = System.argv()
Menard.Lsp.warm(dir)
deadline = System.monotonic_time(:second) + 600

wait = fn wait ->
  cond do
    Menard.Lsp.warm?(dir) -> IO.puts("expert warm in #{dir}")
    System.monotonic_time(:second) > deadline -> raise "expert not ready in #{dir} after 600s"
    true -> Process.sleep(1_000) && wait.(wait)
  end
end

wait.(wait)
