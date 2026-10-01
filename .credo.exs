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
      },
      # a module's attributes, then its public functions, then its private ones: the layout
      # menard's writes keep (Menard.Layout), so a place is never a choice to make
      checks: %{
        extra: [
          {
            Credo.Check.Readability.StrictModuleLayout,
            # a test's tags go above the test they tag
            order: ~w/shortdoc moduledoc behaviour module_attribute public_fun private_fun/a,
            ignore_module_attributes: ~w/tag describetag moduletag/a,
            ignore:
              ~w/use import alias require type typep opaque callback macrocallback optional_callbacks defstruct public_macro private_macro public_guard private_guard callback_impl module/a
          }
        ]
      }
    }
  ]
}
