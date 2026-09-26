defmodule Menard.FindTest do
  # The search verb: what grep is for code that knows what a call, a def, or an alias is.
  # Every hit is `{file, line, column, kind, text}` — data, not a coloured line.
  use ExUnit.Case, async: true

  alias Menard.Find

  @src """
  defmodule Demo do
    alias Server.Channels
    # Channels.general in a comment does not count
    def home(ws), do: Channels.general(ws.id)
    def other(ws), do: Server.Channels.general(ws.id)
    defp general(x), do: x
    def go, do: general(1) <> "Channels.general(2)"
  end
  """

  test "calls: a remote call by Mod.fun, aliased or fully qualified, not strings or comments" do
    hits = Find.calls(@src, "Server.Channels.general")
    assert Enum.map(hits, & &1.line) == [4, 5]
    assert Enum.all?(hits, &(&1.kind == :call))
    assert hd(hits).text =~ "Channels.general(ws.id)"
  end

  test "calls: a local call by bare name" do
    assert [%{line: 7}] = Find.calls(@src, "general")
  end

  test "calls: `__MODULE__.fun()` is a call to the module it is written in" do
    src = """
    defmodule A do
      def go, do: __MODULE__.x()

      defmodule Inner do
        def go, do: __MODULE__.x() + __MODULE__.Deep.x()
      end
    end
    """

    assert [%{line: 2, text: "__MODULE__.x()"}] = Find.calls(src, "A.x")
    assert [%{line: 5, column: 17}] = Find.calls(src, "A.Inner.x")
    assert [%{line: 5, column: 34}] = Find.calls(src, "A.Inner.Deep.x")
  end

  test "calls parses the source once: its passes share the parse cache" do
    # traced in a fresh process, whose parse cache is cold; a process cannot be its own tracer
    src = @src
    task = Task.async(fn -> receive(do: (:go -> Find.calls(src, "Server.Channels.general"))) end)
    Code.ensure_loaded!(Sourceror)
    :erlang.trace_pattern({Sourceror, :parse_string, 1}, true, [])
    :erlang.trace(task.pid, true, [:call])
    send(task.pid, :go)
    assert [_, _] = Task.await(task)
    ref = :erlang.trace_delivered(task.pid)
    assert_receive {:trace_delivered, _, ^ref}
    :erlang.trace_pattern({Sourceror, :parse_string, 1}, false, [])

    parses =
      Stream.repeatedly(fn -> receive(do: ({:trace, _, :call, {_, _, [^src]}} -> 1), after: (0 -> nil)) end)

    assert parses |> Enum.take_while(& &1) |> length() == 1
  end

  test "a name the source never mentions makes no atom: the VM never collects one" do
    name = "never_found_#{System.unique_integer([:positive])}"
    assert Find.calls(@src, name) == []
    assert Find.calls(@src, "Server.Channels.#{name}") == []
    assert Find.defs(@src, name <> "/1") == []
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end

  test "defs: by name, any arity or a given one" do
    assert [%{line: 6, kind: :defp, text: "defp general(x)"}] = Find.defs(@src, "general")
    assert [] = Find.defs(@src, "general/2")
    assert [%{line: 4}] = Find.defs(@src, "home/1")
  end

  test "aliases: where a module is aliased" do
    assert [%{line: 2, kind: :alias}] = Find.aliases(@src, "Server.Channels")
  end

  test "calls resolves `alias __MODULE__.X` against the module it sits in" do
    src = """
    defmodule A do
      alias __MODULE__.Inner
      def go, do: Inner.x()
    end
    """

    assert [%{line: 3}] = Find.calls(src, "A.Inner.x")
  end

  test "the CLI: the kind once, a directory searched, a path that matches nothing named" do
    dir = Path.join(System.tmp_dir!(), "menard-find-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "lib/deep"))
    on_exit(fn -> File.rm_rf!(dir) end)
    File.write!(Path.join(dir, "lib/deep/a.ex"), "defmodule A do\n  def go(x), do: x\nend\n")
    find = fn args -> ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Menard.Find.run(args) end) end

    # the kind once: `def go(x)`, not `def def go(x)`
    assert find.(["defs", "go", Path.join(dir, "lib/deep/a.ex")]) =~ ~r/:2:3 def go\(x\)\n\z/

    # a directory is searched, not a File.Error
    assert find.(["defs", "go", Path.join(dir, "lib")]) =~ "a.ex:2:3 def go(x)"

    # a path that matches nothing is named, not an empty answer that reads as "no references"
    missing = Path.join(dir, "lib/nope.ex")
    assert_raise Mix.Error, ~r/nope\.ex matches no file/, fn -> find.(["defs", "go", missing]) end
  end

  test "calls: a call inside a ~H template, aliased or local, not text around it" do
    # bench1 explore-callers.B.haiku: find answered two callers of four, the two in templates missing
    src = ~S'''
    defmodule Card do
      alias Shop.Catalog

      def card(assigns) do
        ~H"""
        <.price cents={Catalog.price_with_tax(@product)} />
        <p :if={
          Catalog.price_with_tax(@p) > 0 and local(@p)
        }>Catalog.price_with_tax(1) in text</p>
        """
      end

      defp local(x), do: x
    end
    '''

    assert [%{line: 6, column: 20, kind: :call}, %{line: 8, column: 7}] =
             Find.calls(src, "Shop.Catalog.price_with_tax")

    assert hd(Find.calls(src, "Shop.Catalog.price_with_tax")).text =~ "Catalog.price_with_tax(@product)"
    assert [%{line: 8}] = Find.calls(src, "local")
  end

  @tag :tmp_dir
  test "left answers, never raises: an empty lib/, a file it cannot read", %{tmp_dir: root} do
    # a whole-function delete has already written when left runs: a raise here lost the reply
    File.mkdir_p!(Path.join(root, "lib"))
    File.mkdir_p!(Path.join(root, "test"))
    File.ln_s!("nowhere.exs", Path.join(root, "test/gone_test.exs"))
    file = Path.join(root, "a.ex")
    source = "defmodule A do\n  def run, do: go()\nend\n"
    File.write!(file, source)

    assert Find.left(root, file, source, "go/0") == [
             "a.ex:2: go()",
             "test/gone_test.exs: not read (no such file or directory)"
           ]
  end
end
