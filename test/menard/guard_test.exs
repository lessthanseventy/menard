defmodule Menard.GuardTest do
  # `menard guard FILE`: the enforcement logic any harness's pre-edit hook calls — refused with the
  # reason for an Elixir module, allowed for everything else. The verb is called here in the test's
  # VM; the hook's side of it (exit 2 with the reason on stderr, 0 otherwise) is hooks_test's,
  # through the real hook and bin/menard.
  use ExUnit.Case, async: true

  alias Menard.Verbs.Guard

  @moduletag :tmp_dir

  defp guard(file, params \\ %{}) do
    {:ok, reply} = Guard.run(Map.put(params, :file, file))
    reply
  end

  test "an existing module is refused, with the verbs to use instead", %{tmp_dir: dir} do
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\nend\n")

    assert %{allowed: false, reason: out} = guard(file)
    assert out =~ "an Elixir module"
    assert out =~ "clause replace"
  end

  test "a new file, a non-module script and other languages pass", %{tmp_dir: dir} do
    script = Path.join(dir, "run.exs")
    File.write!(script, "IO.puts(:hi)\n")
    other = Path.join(dir, "a.ts")
    File.write!(other, "defmodule\n")

    assert %{allowed: true} = guard(Path.join(dir, "new.ex"))
    assert %{allowed: true} = guard(script)
    assert %{allowed: true} = guard(other)
  end

  test "config, deps, _build and .formatter.exs are exempt", %{tmp_dir: dir} do
    for rel <- ["config/config.exs", "deps/x/lib/x.ex", "_build/dev/x.ex", ".formatter.exs"] do
      file = Path.join(dir, rel)
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, "defmodule X do\nend\n")
      assert %{allowed: true} = guard(file), rel
    end
  end

  test "with --mcp the refusal names the MCP tools and their fields, not CLI lines a blocked agent then runs through Bash",
       %{tmp_dir: dir} do
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\nend\n")

    %{allowed: false, reason: out} = guard(file, %{mcp: "mcp__plugin_menard_menard__"})

    assert out =~ "mcp__plugin_menard_menard__clause"
    assert out =~ "name_arity"
    refute out =~ "bin/menard"
  end

  describe "--edit: an edit that only changes text inside strings passes" do
    @src ~S'''
    defmodule Shop.Mailer do
      # the receipt
      @receipt """
      Total: {{totl}}
      """

      def render(assigns) do
        ~H"""
        <p>{Cart.total(@cart)}</p>
        """
      end

      def hi(name), do: "hi #{name}"
    end
    '''

    setup %{tmp_dir: dir} do
      file = Path.join(dir, "mailer.ex")
      File.write!(file, @src)
      %{mailer: file}
    end

    defp edit(file, input), do: guard(file, %{edit: JSON.encode!(input)})

    test "a heredoc attribute's text and a ~H template's text pass", %{mailer: file} do
      assert %{allowed: true} = edit(file, %{old_string: "{{totl}}", new_string: "{{total}}"})

      assert %{allowed: true} =
               edit(file, %{old_string: "Cart.total(@cart)", new_string: "Cart.total(@cart, rate)"})
    end

    test "MultiEdit and Write are judged the same way, on the file they would leave", %{mailer: file} do
      assert %{allowed: true} =
               edit(file, %{
                 edits: [
                   %{old_string: "totl", new_string: "total"},
                   %{old_string: "<p>", new_string: "<p class=\"t\">"}
                 ]
               })

      assert %{allowed: true} = edit(file, %{content: String.replace(@src, "totl", "total")})
      assert %{allowed: false} = edit(file, %{content: String.replace(@src, "hi(name)", "hi(first)")})
    end

    test "code is refused, even code interpolated into a string", %{mailer: file} do
      assert %{allowed: false, reason: out} =
               edit(file, %{old_string: "def hi(name)", new_string: "def hi(first)"})

      assert out =~ "an Elixir module"
      assert %{allowed: false} = edit(file, %{old_string: "\#{name}", new_string: "\#{String.upcase(name)}"})
    end

    test "a comment passes: no verb reaches prose, and the tree is the same without it", %{mailer: file} do
      assert %{allowed: true} = edit(file, %{old_string: "# the receipt", new_string: "# the mail"})
      assert %{allowed: true} = edit(file, %{old_string: "  # the receipt\n", new_string: ""})

      assert %{allowed: true} =
               edit(file, %{old_string: "  def hi(name)", new_string: "  # says hi\n  def hi(name)"})
    end

    test "an edit that breaks the parse, or does not apply, is refused", %{mailer: file} do
      assert %{allowed: false} = edit(file, %{old_string: "Total: {{totl}}\n  \"\"\"", new_string: "Total"})
      assert %{allowed: false} = edit(file, %{old_string: "not in the file", new_string: "x"})
    end

    test "pi's edit shape is judged the same way", %{mailer: file} do
      assert %{allowed: true} =
               edit(file, %{path: file, edits: [%{oldText: "{{totl}}", newText: "{{total}}"}]})

      assert %{allowed: false} =
               edit(file, %{path: file, edits: [%{oldText: "def hi(name)", newText: "def hi(first)"}]})
    end

    test "the MCP refusal does not send an agent to ToolSearch for tools that are already loaded", %{
      mailer: file
    } do
      # with alwaysLoad the tools are in context; the old "Not loaded yet: ToolSearch …" line cost two
      # smoke runs a round trip each
      %{allowed: false, reason: out} = guard(file, %{mcp: "mcp__plugin_menard_menard__"})

      refute out =~ ~s(ToolSearch "select:)
    end
  end
end
