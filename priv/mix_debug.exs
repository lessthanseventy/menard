# Required before `mix precommit` (`elixir -r THIS -S mix precommit`) by `run check`: mix's task
# trace on, so the alias step that failed is named by the one mix started and never finished.
# Mix.debug and not MIX_DEBUG: the variable reaches every process the alias starts (a host's tests
# running mix print the trace into what they assert on); Mix.CLI starts mix again, and keeps this.
Mix.start()
Mix.debug(true)
