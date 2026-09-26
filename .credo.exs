# menard's own lint runs --strict (the precommit alias); a host's is its own choice, and menard's
# `run check` does not add --strict to it. test/fixtures is source the tests READ, odd on purpose
# (the identity corpus), not code to lint.
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "priv/", "test/", "config/"],
        excluded: [~r"/_build/", ~r"/deps/", "test/fixtures/"]
      }
    }
  ]
}
