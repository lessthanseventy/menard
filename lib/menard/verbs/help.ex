defmodule Menard.Verbs.Help do
  @moduledoc """
  The `help` verb (`Menard.Verbs`): what menard's verbs are for, by example. With no `verb`, every
  verb in a line and the call it is most reached for; with one, what it does, the calls it takes
  and an example of each kind. The reply is `text`, written to be read: it is what `--help`
  prints.

  An agent learns a tool from what the tool says when it is asked or got wrong, so this says it
  the way it is typed: every call by this menard's path, with arguments that could be real.
  """

  alias Menard.Verbs.Noun

  # {verb, what it is for, [example]}: the first example is the one the overview shows. `menard`
  # stands for this menard's path, put in when the text is made.
  @verbs [
    {"edit", "replace text, in several places and files, in one call, all written or none",
     [
       "menard edit --then test - <<'EOF'\nlib/shop/cart.ex\n<<<<<<< SEARCH\n  def total(cart), do: sum(cart)\n=======\n  def total(cart, rate), do: sum(cart) * (1 + rate)\n>>>>>>> REPLACE\ntest/shop/cart_test.exs\n<<<<<<< SEARCH\nCart.total(cart)\n=======\nCart.total(cart, 0.2)\n>>>>>>> REPLACE\nEOF"
     ]},
    {"rename", "a name changed everywhere it is used; strings and comments left alone",
     ["menard rename price_with_tax price_including_tax 'lib/**/*.ex' 'test/**/*.exs'"]},
    {"find", "who calls a function, where a name is defined: grep that knows the code",
     ["menard find calls Shop.Cart.total 'lib/**/*.ex'", "menard find defs total/2 lib test"]},
    {"outline", "a file's modules and functions, with their heads and lines, in place of reading it",
     ["menard outline lib/shop/cart.ex"]},
    {"clause", "one function or clause: read, replaced, moved with its docs; a module split",
     [
       "menard clause get lib/shop/cart.ex total/2",
       "menard clause replace lib/shop/cart.ex total/2 'cart, rate' 'sum(cart) * (1 + rate)'",
       "menard clause move lib/shop.ex list/0,get/1 --to lib/shop/catalog.ex --delegate",
       ~s(menard clause split lib/shop.ex lib/shop/catalog.ex=list/0,get/1 lib/shop/pricing.ex=total/2,net/1)
     ]},
    {"stmt", "one statement inside a function, by what is written",
     ["menard stmt replace lib/shop/cart.ex total/2 'cart, rate' 'rate =' 'rate = rate || 0.2'"]},
    {"block", "a test, a describe, a schema: a macro's do block, by its label",
     [
       ~s|menard block add test/shop/cart_test.exs test --label "totals with tax" 'assert Cart.total(cart, 0.2) == 12'|,
       ~s(menard block get test/shop/cart_test.exs test --label "totals with tax")
     ]},
    {"attr", "a module attribute",
     ["menard attr get lib/shop/cart.ex rate", "menard attr set lib/shop/cart.ex rate 0.2"]},
    {"directive", "an alias, import, require or use, put where it belongs",
     ["menard directive add lib/shop/cart.ex alias Shop.Catalog"]},
    {"module", "one whole module of a file that holds several", ["menard module list lib/shop.ex"]},
    {"write", "a whole file, parse-checked and formatted",
     ["menard write lib/shop/new.ex - <<'EOF'\ndefmodule Shop.New do\nend\nEOF"]},
    {"deps", "what a function uses; a dependency added or upgraded",
     ["menard deps lib/shop/cart.ex total/2", ~s(menard deps add '{:req, "~> 0.5"}')]},
    {"run", "tests, the gate, compile, format, credo: one JSON line, every failure with its file and line",
     ["menard run test test/shop/cart_test.exs:12", "menard run check"]},
    {"map", "every module of the project, its file and public functions", ["menard map"]},
    {"where", "the function a file:line is in", ["menard where lib/shop/cart.ex:42"]},
    {"version", "which menard this is", ["menard version"]}
  ]

  @doc "The verbs `help` knows, in the order it lists them."
  @spec verbs() :: [String.t()]
  def verbs, do: for({verb, _what, _examples} <- @verbs, do: verb)

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(%{verb: verb}) when is_binary(verb) and verb != "" do
    case List.keyfind(@verbs, verb, 0) do
      {^verb, what, examples} -> {:ok, %{text: one(verb, what, examples)}}
      nil -> {:error, "menard has no verb #{verb}: one of #{Enum.join(verbs(), ", ")}"}
    end
  end

  def run(_params), do: {:ok, %{text: all()}}

  defp all do
    width = verbs() |> Enum.map(&String.length/1) |> Enum.max()

    lines =
      for {verb, what, [example | _]} <- @verbs do
        first = example |> String.split("\n") |> hd()
        more = if first == example, do: "", else: " …"

        "  #{String.pad_trailing(verb, width)}  #{what}\n  #{String.duplicate(" ", width)}    #{at(first)}#{more}"
      end

    """
    menard: AST-aware edits and structured runs for Elixir. Every write is parse-checked and \
    formatted with the project's own formatter.

    #{Enum.join(lines, "\n")}

    #{Menard.bin()} VERB --help   what a verb takes, with an example of each call
    A path is relative to the directory you are in. CODE full of quotes goes on stdin: `-` in its place.
    """
  end

  defp one(verb, what, examples) do
    """
    #{verb}: #{what}

    #{Enum.map_join(examples, "\n\n", &indent(at(&1)))}
    #{calls(verb)}\
    """
  end

  # the calls a noun takes, where it declares them, and what it says of itself
  defp calls(verb) do
    case Enum.find(Noun.modules(), &(Noun.of(&1).name == verb)) do
      nil -> ""
      verbs -> "\n" <> shapes(Noun.of(verbs)) <> String.trim_trailing(Noun.of(verbs).doc) <> "\n"
    end
  end

  defp shapes(%{cli: _} = noun), do: "calls:\n  " <> Menard.CLI.as_run(Noun.usage(noun)) <> "\n\n"
  defp shapes(_noun), do: ""

  defp at(example), do: String.replace_prefix(example, "menard ", Menard.bin() <> " ")
  defp indent(text), do: text |> String.split("\n") |> Enum.map_join("\n", &("  " <> &1))
end
