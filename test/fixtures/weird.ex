# Parsed by the identity check, never compiled: as many shapes of valid Elixir as fit in one file,
# weighted toward the ones that have broken a verb — heredocs, literal and `do:` bodies, keywords
# inside keywords, multi-aliases, `__MODULE__`, comments in odd places.
defmodule Weird do
  @moduledoc """
  A module with #{"interpolation"} in its doc,
  and a second line.
  """
  @behaviour Weird.Behaviour

  use GenServer, restart: :transient
  import Enum, only: [map: 2, reduce: 3]
  import Kernel, except: [inspect: 1]
  alias Weird.{Inner, Other.Deep}
  alias __MODULE__.Nested
  alias Some.Long.Name, as: Short
  require Logger

  @derive {Inspect, only: [:a]}
  @enforce_keys [:a]
  defstruct a: nil, b: %{}, c: []

  @type t :: %__MODULE__{a: term(), b: map(), c: list()}
  @type maybe(x) :: x | nil
  @typep private :: :one | :two | {:three, integer()}

  @callback go(term()) :: :ok | {:error, term()}

  # a table, with the comment glued above it
  @colors %{
    red: "#f00",
    green: "#0f0"
  }
  @limit 5_000
  @derived @limit * 2
  @names ~w(one two three)a
  @pattern ~r/^weird(?<n>\d+)$/iu
  @raw ~S"""
  no #{interpolation} here \n
  """
  @empty false
  @nothing nil
  @charlist ~c"chars"
  @quoted :"an atom with spaces"

  Module.register_attribute(__MODULE__, :acc, accumulate: true)
  @acc :first
  @acc :second

  @doc false
  def zero, do: :zero

  def zero_parens(), do: :parens

  @doc "Defaults, and a bodiless head to carry them."
  @spec defaults(term(), integer()) :: term()
  def defaults(a, b \\ 1)
  def defaults(nil, _b), do: nil
  def defaults(a, b) when is_integer(a) and b > 0 when is_float(a), do: a + b

  def literal_false(_node), do: false
  def literal_nil(_node), do: nil
  def literal_tuple(x), do: {:ok, x}
  def literal_list(x), do: [x | [x]]
  def literal_map(x), do: %{x => x, "k" => 1, a: x}

  def keyword_if(x), do: if(x, do: :yes, else: :no)
  def keyword_with(x), do: with({:ok, y} <- x, do: y)

  def binary(<<a::8, rest::binary>> = whole, <<"prefix", _::binary>>) do
    {a, rest, byte_size(whole)}
  end

  def struct_match(%__MODULE__{a: a} = s, %{b: ^a}), do: %{s | a: a}

  def pin(x, y) do
    ^x = y
    x
  end

  def pipes(list) do
    list
    |> map(&(&1 * 2))
    |> Enum.filter(&is_integer/1)
    |> reduce(0, fn x, acc -> x + acc end)
    |> then(fn total -> total * @limit end)
  end

  def withs(a, b) do
    with {:ok, x} <- a,
         # a comment between steps
         {:ok, y} when y > x <- b,
         z = x + y do
      {:ok, z}
    else
      {:error, _} = e -> e
      _other -> :error
    end
  end

  def cases(x) do
    case x do
      # a comment above an arm
      {:ok, v} when is_binary(v) or is_atom(v) ->
        v

      [head | _tail] ->
        head

      %{"key" => value} ->
        value

      nil ->
        false

      _ ->
        :error
    end
  end

  def conds(n) do
    cond do
      n < 0 -> :negative
      n == 0 -> :zero
      true -> :positive
    end
  end

  def receives(timeout) do
    receive do
      {:msg, m} -> m
      :stop -> exit(:normal)
    after
      timeout -> :timeout
    end
  end

  def tries(f) do
    try do
      f.()
    rescue
      e in [ArgumentError, KeyError] -> {:rescued, e}
      _ -> :rescued
    catch
      :throw, value -> {:caught, value}
      :exit, _ -> :exited
    else
      result -> {:ok, result}
    after
      Logger.debug("done")
    end
  end

  def rescue_body(x) do
    Integer.parse(x)
  rescue
    _ -> :error
  end

  def comprehensions(list, bin) do
    a = for x <- list, x > 1, into: %{}, do: {x, x}
    b = for <<c <- bin>>, c != ?\s, do: <<c>>
    c = for x <- list, reduce: 0, do: (acc -> acc + x)
    d = for x <- list, y <- list, uniq: true, do: {x, y}
    {a, b, c, d}
  end

  def fns do
    multi = fn
      {:ok, x} -> x
      _ -> nil
    end

    nested = fn x -> fn y -> x + y end end
    capture = &Deep.go/2
    local = &zero/0
    {multi.({:ok, 1}), nested.(1).(2), capture, local}
  end

  def strings(x) do
    a = "nested #{"inner #{x} quotes"} end"
    b = ~s(parens "and quotes" #{x})
    c = ~w[one two]
    d = 'single' ++ [?a]

    e = """
    heredoc in a body, #{x}
      keeps its indent
    """

    {a, b, c, d, e}
  end

  def unicode(café, naïve), do: {café, naïve, "ünïcödé", :ok?}

  def operators(a, b) do
    r = 1..10//2
    all = ..
    not_in = a not in [b]
    bools = (a && b) || !a
    {r, all, not_in, bools, a <> b, a ++ b, a -- b, a ** 2, rem(a, b), a |> div(b)}
  end

  def unless_raise(x) do
    unless x, do: raise(ArgumentError, "no x")
    x || throw(:none)
  end

  def remote_and_aliased(x) do
    Short.call(x)
    Nested.call(x)
    __MODULE__.zero()
    Inner.call(x) |> Deep.call()
    :erlang.phash2(x)
    Weird.Other.Deep.call(x)
  end

  def a <~> b, do: {a, b}

  defguard is_weird(x) when is_atom(x) and x not in [nil, true, false]

  defmacro weird_macro(ast) do
    quote do
      unquote(ast) |> then(fn x -> {unquote(__MODULE__), x} end)
    end
  end

  defdelegate delegated(x), to: Enum, as: :count

  # a comment between definitions

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:get, _from, state), do: {:reply, state, state}

  def handle_call({:put, v}, _from, _state) do
    {:reply, :ok, v}
  end

  defp private_last(x), do: x

  defmodule Inner do
    @moduledoc false
    def call(x), do: x
    def zero, do: :inner
  end
end

defprotocol Weird.Proto do
  @fallback_to_any true
  def describe(term)
end

defimpl Weird.Proto, for: Weird do
  def describe(%Weird{a: a}), do: "weird #{inspect(a)}"
end

defmodule Weird.Error do
  defexception message: "weird", code: nil

  @impl true
  def exception(opts), do: %__MODULE__{code: opts[:code]}
end

defmodule WeirdTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, thing: :value}
  end

  setup :other_setup

  describe "a describe" do
    test "with context", %{thing: thing} do
      assert thing == :value
    end

    test "a do: test", do: assert(true)

    @tag :skip
    test "a heredoc ends it" do
      assert Weird.strings(1) =~ """
             heredoc
             """
    end
  end

  test "outside any describe" do
    refute nil
  end

  schema "things" do
    field(:name, :string)
    field(:count, :integer, default: 0)
    timestamps()
  end
end

# a comment above defmodule, and attributes read by a moduledoc, a use and each other
defmodule Weird.Templates do
  @dir "priv/templates"
  @moduledoc "templates in #{@dir}"
  use Weird.Templating, from: @dir

  @other @dir <> "/other"

  def go, do: @other
end
