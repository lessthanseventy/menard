defmodule Mix.Tasks.Menard.Edit do
  @shortdoc "Replace text, in several files, in one call: mix menard.edit [--then test|check|compile] BLOCKS|-"
  @moduledoc """
  `mix menard.edit [--then test|check|compile] BLOCKS` — several replacements in one call, all
  written or none (`Menard.Edit`). BLOCKS is search/replace blocks, `-` to read them from stdin:

      menard edit --then test - <<'EOF'
      lib/shop/cart.ex
      <<<<<<< SEARCH
        def total(cart), do: sum(cart)
      =======
        def total(cart, rate), do: sum(cart) * (1 + rate)
      >>>>>>> REPLACE
      test/shop/cart_test.exs
      <<<<<<< SEARCH
      Cart.total(cart)
      =======
      Cart.total(cart, 0.2)
      >>>>>>> REPLACE
      EOF

  The text between SEARCH and `=======` is found exactly once in the file, or the call is refused
  and says which text was not there, or was there twice. `--all` takes every occurrence, of every
  block. An empty search makes a new file. `--then` runs that verb after, its answer under `run`.
  """
  use Mix.Task

  alias Menard.Verbs

  import Menard.CLI

  @usage "mix menard.edit [--then test|check|compile] [--all] BLOCKS   (BLOCKS of `-` reads stdin)\n" <>
           "       a block: FILE, `<<<<<<< SEARCH`, the text to find, `=======`, the text to put there, `>>>>>>> REPLACE`"

  @impl true
  def run(argv) do
    case options(argv, then: :string, all: :boolean) do
      {flags, [blocks]} -> edit(stdin(blocks, "menard.edit"), flags)
      _ -> usage(@usage)
    end
  end

  defp edit(blocks, flags) do
    case Menard.Edit.blocks(blocks) do
      {:ok, edits} ->
        edits = Enum.map(edits, &Map.put(&1, :all, flags[:all] == true))
        finish(Verbs.Edit.run(%{edits: edits, then: flags[:then]}))

      {:error, why} ->
        usage(why <> "\n       " <> @usage)
    end
  end
end
