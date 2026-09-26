defmodule Menard.GuardTest do
  # `menard guard FILE`: the enforcement logic any harness's pre-edit hook calls — exit 2 with the
  # reason on stderr for an Elixir module, 0 for everything else.
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @bin Path.expand("../../bin/menard", __DIR__)

  defp guard(file), do: System.cmd(@bin, ["guard", file], stderr_to_stdout: true, env: [{"MIX_ENV", "dev"}])

  test "an existing module is refused, with the verbs to use instead", %{tmp_dir: dir} do
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\nend\n")

    assert {out, 2} = guard(file)
    assert out =~ "an Elixir module"
    assert out =~ "clause replace"
  end

  test "a new file, a non-module script and other languages pass", %{tmp_dir: dir} do
    script = Path.join(dir, "run.exs")
    File.write!(script, "IO.puts(:hi)\n")
    other = Path.join(dir, "a.ts")
    File.write!(other, "defmodule\n")

    assert {_, 0} = guard(Path.join(dir, "new.ex"))
    assert {_, 0} = guard(script)
    assert {_, 0} = guard(other)
  end

  test "config, deps, _build and .formatter.exs are exempt", %{tmp_dir: dir} do
    for rel <- ["config/config.exs", "deps/x/lib/x.ex", "_build/dev/x.ex", ".formatter.exs"] do
      file = Path.join(dir, rel)
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, "defmodule X do\nend\n")
      assert {_, 0} = guard(file), rel
    end
  end

  test "with --mcp the refusal names the MCP tools and their fields, not CLI lines a blocked agent then runs through Bash",
       %{tmp_dir: dir} do
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\nend\n")

    {out, 2} =
      System.cmd(@bin, ["guard", file, "--mcp", "mcp__plugin_menard_menard__"],
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "dev"}]
      )

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

    defp edit(file, input),
      do:
        System.cmd(@bin, ["guard", file, "--edit", JSON.encode!(input)],
          stderr_to_stdout: true,
          env: [{"MIX_ENV", "dev"}]
        )

    test "a heredoc attribute's text and a ~H template's text pass", %{mailer: file} do
      assert {_, 0} = edit(file, %{old_string: "{{totl}}", new_string: "{{total}}"})
      assert {_, 0} = edit(file, %{old_string: "Cart.total(@cart)", new_string: "Cart.total(@cart, rate)"})
    end

    test "MultiEdit and Write are judged the same way, on the file they would leave", %{mailer: file} do
      assert {_, 0} =
               edit(file, %{
                 edits: [
                   %{old_string: "totl", new_string: "total"},
                   %{old_string: "<p>", new_string: "<p class=\"t\">"}
                 ]
               })

      assert {_, 0} = edit(file, %{content: String.replace(@src, "totl", "total")})
      assert {_, 2} = edit(file, %{content: String.replace(@src, "hi(name)", "hi(first)")})
    end

    test "code is refused, even code interpolated into a string", %{mailer: file} do
      assert {out, 2} = edit(file, %{old_string: "def hi(name)", new_string: "def hi(first)"})
      assert out =~ "an Elixir module"
      assert {_, 2} = edit(file, %{old_string: "\#{name}", new_string: "\#{String.upcase(name)}"})
    end

    test "a comment passes: no verb reaches prose, and the tree is the same without it", %{mailer: file} do
      assert {_, 0} = edit(file, %{old_string: "# the receipt", new_string: "# the mail"})
      assert {_, 0} = edit(file, %{old_string: "  # the receipt\n", new_string: ""})
      assert {_, 0} = edit(file, %{old_string: "  def hi(name)", new_string: "  # says hi\n  def hi(name)"})
    end

    test "an edit that breaks the parse, or does not apply, is refused", %{mailer: file} do
      assert {_, 2} = edit(file, %{old_string: "Total: {{totl}}\n  \"\"\"", new_string: "Total"})
      assert {_, 2} = edit(file, %{old_string: "not in the file", new_string: "x"})
    end

    test "pi's edit shape is judged the same way", %{mailer: file} do
      assert {_, 0} = edit(file, %{path: file, edits: [%{oldText: "{{totl}}", newText: "{{total}}"}]})
      assert {_, 2} = edit(file, %{path: file, edits: [%{oldText: "def hi(name)", newText: "def hi(first)"}]})
    end

    test "the MCP refusal does not send an agent to ToolSearch for tools that are already loaded", %{
      tmp_dir: dir
    } do
      # with alwaysLoad the tools are in context; the old "Not loaded yet: ToolSearch …" line cost two
      # smoke runs a round trip each
      file = Path.join(dir, "a.ex")
      File.write!(file, "defmodule A do\nend\n")

      {out, 2} =
        System.cmd(@bin, ["guard", file, "--mcp", "mcp__plugin_menard_menard__"],
          stderr_to_stdout: true,
          env: [{"MIX_ENV", "dev"}]
        )

      # the instruction, not the word: this test's own tmp dir is named after it
      refute out =~ ~s(ToolSearch "select:)
    end
  end
end
