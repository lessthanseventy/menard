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

  @usage "mix menard.edit [--then test [FILE…]|check|compile] [--all] [--retry N] BLOCKS   (BLOCKS of `-` reads stdin)\n" <>
           "       a block: FILE, `<<<<<<< SEARCH`, the text to find, `=======`, the text to put there, `>>>>>>> REPLACE`"

  @impl true
  def run(argv) do
    # `--then test FILE… BLOCKS`: the files before the blocks are the then's, as the MCP door's
    # `then: "test FILE…"` names them. Written so seven times in a week, refused with the bare usage
    # line each time, and the edit sent again without its `--then` at all
    case options(argv, then: :string, all: :boolean, retry: :integer) do
      {flags, [blocks]} ->
        edit(stdin(blocks, "menard.edit"), flags)

      {flags, [_, _ | _] = args} ->
        case flags[:then] do
          nil ->
            usage(@usage)

          then ->
            edit(
              stdin(List.last(args), "menard.edit"),
              Keyword.put(flags, :then, Enum.join([then | Enum.drop(args, -1)], " "))
            )
        end

      _ ->
        usage(@usage)
    end
  end

  defp edit(blocks, flags) do
    with {:ok, edits} <- Menard.Edit.blocks(blocks),
         {:ok, edits} <- retried(edits, flags[:retry]) do
      edits = Enum.map(edits, &Map.put(&1, :all, flags[:all] == true))

      case Verbs.call(Verbs.Edit, %{edits: edits, then: flags[:then]}) do
        {:error, why} -> finish({:error, kept(edits, why)})
        reply -> finish(reply)
      end
    else
      {:error, why} -> usage(why <> "\n       " <> @usage)
    end
  end

  # A refusal names one edit of the batch; the batch is kept, and `--retry N` takes that one again,
  # corrected, with the rest as they were. Before, the whole batch was sent again: 22 of ~270
  # edits in one session, 45 KB (Fable's review, 2026-10-01)
  defp kept(edits, why) do
    with [_, n, total] <- Regex.run(~r/^edit (\d+) of (\d+),/, why),
         true <- total != "1" do
      File.write!(kept_path(), :erlang.term_to_binary(edits))

      why <>
        "\nThe other #{String.to_integer(total) - 1} are kept: send edit #{n} corrected, alone, as\n" <>
        "  #{Menard.command("edit")} --retry #{n} - <<'EOF'\n  FILE\n  <<<<<<< SEARCH\n  …\n  EOF"
    else
      _ -> why
    end
  end

  defp retried(edits, nil), do: {:ok, edits}

  defp retried(sent, n) do
    case File.read(kept_path()) do
      {:ok, kept} ->
        kept = :erlang.binary_to_term(kept)

        if n in 1..length(kept)//1,
          do: {:ok, List.flatten(List.replace_at(kept, n - 1, sent))},
          else: {:error, "nothing kept to retry as edit #{n}: the last refused batch had #{length(kept)}"}

      {:error, _} ->
        {:error, "nothing kept to retry: no edit of this project's was refused with its edits kept"}
    end
  end

  defp kept_path,
    do:
      Path.join(
        System.tmp_dir!(),
        "menard-edit-kept-" <> Base.url_encode64(Menard.caller_dir(), padding: false)
      )
end
