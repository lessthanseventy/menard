defmodule Menard.LangTest do
  # A write's safety net for what is not Elixir. Each tool real: what one prints is the contract,
  # and a stub would only say what was assumed of it.
  use ExUnit.Case, async: true

  alias Menard.Lang
  alias Menard.Verbs

  @moduletag :tmp_dir

  @messy "if true; then\n      echo hi\nfi\n"
  @tidy "if true; then\n\techo hi\nfi\n"

  defp repo(dir, files) do
    for {name, code} <- files, do: File.write!(Path.join(dir, name), code)

    for args <- [~w(init -q), ~w(add -A), ~w(-c user.name=t -c user.email=t@t commit -q -m one)],
        do: git(dir, args)

    dir
  end

  defp git(dir, args), do: {_, 0} = System.cmd("git", ["-C", dir | args], stderr_to_stdout: true)
  defp edit(dir, edits), do: Verbs.call(Verbs.Edit, %{root: dir, edits: edits})

  test "shell that does not parse is refused, and nothing is written", %{tmp_dir: dir} do
    repo(dir, [{"a.sh", @tidy}])

    assert {:error, why} = edit(dir, [%{file: "a.sh", old: "fi\n", new: ""}])
    assert why =~ "a.sh: with these edits it is not parseable"
    assert why =~ "nothing was written"
    assert File.read!(Path.join(dir, "a.sh")) == @tidy
  end

  test "Nix that does not parse is refused", %{tmp_dir: dir} do
    assert {:error, "not parseable: " <> why} = Lang.parse(Path.join(dir, "a.nix"), "{ a = [ ; }\n")
    assert why =~ "syntax error"
    assert :ok = Lang.parse(Path.join(dir, "a.nix"), "{ a = 1; }\n")
  end

  test "a file in its formatter's style at HEAD is formatted, and the reply says so", %{tmp_dir: dir} do
    repo(dir, [{"a.sh", @tidy}])

    assert {:ok, reply} = edit(dir, [%{file: "a.sh", old: "\techo hi", new: "      echo there"}])
    assert File.read!(Path.join(dir, "a.sh")) == "if true; then\n\techo there\nfi\n"
    assert [%{stages: [%{stage: :formatter}]}] = reply.changed
  end

  test "a file not in its formatter's style at HEAD is left in its own", %{tmp_dir: dir} do
    repo(dir, [{"a.sh", @messy}])

    assert {:ok, _reply} = edit(dir, [%{file: "a.sh", old: "echo hi", new: "echo there"}])
    assert File.read!(Path.join(dir, "a.sh")) == "if true; then\n      echo there\nfi\n"
  end

  test "a new file in a repo is formatted; outside one, it has no history to go by", %{tmp_dir: dir} do
    # outside any repo: the test's own tmp_dir is under menard's
    outside =
      Path.join(System.tmp_dir!(), "menard-lang-#{System.pid()}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(outside)
    on_exit(fn -> File.rm_rf!(outside) end)
    assert Lang.format(Path.join(outside, "a.sh"), @messy) == @messy

    repo(dir, [{"other", ""}])
    assert Lang.format(Path.join(dir, "a.sh"), @messy) == @tidy
  end

  test "lint is on the lines changed, not the debt around them", %{tmp_dir: dir} do
    repo(dir, [{"a.sh", "#!/bin/bash\necho $1\necho ok\n"}])

    assert {:ok, %{changed: [%{lint: [found]}]}} =
             edit(dir, [%{file: "a.sh", old: "echo ok", new: "echo $2"}])

    assert %{kind: "shellcheck", at: "a.sh:3", message: "SC2086: " <> _} = found
  end

  test "a sibling the script sources is followed, and its own debt is not the script's", %{tmp_dir: dir} do
    # the hook said "SC1091: Not following: ./lib.sh" of a hook that sources lib.sh as every hook
    # does, which the gate's own shellcheck (-x -P SCRIPTDIR) follows; followed, lib.sh's lines
    # are lib.sh's, not line 3 of the script
    repo(dir, [
      {"lib.sh", "# shellcheck shell=bash\nx=1\necho $x\n"},
      {"a.sh", "#!/bin/bash\necho ok\n"}
    ])

    assert {:ok, %{changed: [%{lint: found}]}} =
             edit(dir, [
               %{
                 file: "a.sh",
                 old: "echo ok",
                 new: ~S|source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"| <> "\necho $1 $x"
               }
             ])

    assert [%{kind: "shellcheck", at: "a.sh:3", message: "SC2086: " <> _}] = found
  end

  test "a script with no extension has a row by its shebang, and a .sh of zsh's is zsh's", %{tmp_dir: dir} do
    assert {:error, "not parseable" <> _} =
             Lang.parse(Path.join(dir, "run"), "#!/usr/bin/env bash\nif true; then\n")

    assert Lang.known?("bin/x", "#!/bin/sh\n")
    assert :ok = Lang.parse(Path.join(dir, "notes"), "if true; then\n")
    refute Lang.known?("bin/y", "#!/usr/local/sh/python\n")

    # zsh's own syntax, which bash -n refuses
    zsh = "#!/bin/zsh\nfor i ({1..3}) echo $i\n"
    assert :ok = Lang.parse(Path.join(dir, "a.sh"), zsh)

    assert {:error, "not parseable: " <> _} =
             Lang.parse(Path.join(dir, "a.sh"), "#!/bin/zsh\nfor i ({1..3}\n")

    assert Lang.known?("bin/z", "#!/usr/bin/env zsh\n")
    refute Lang.known?("bin/f", "#!/usr/bin/env fish\n")
  end

  test "zsh that does not parse is refused, with its line", %{tmp_dir: dir} do
    assert {:error, "not parseable: " <> why} =
             Lang.parse(Path.join(dir, "a.zsh"), "print one\nif [[ -n $x ]] {\n")

    assert why =~ ~r/:3: parse error/
    assert :ok = Lang.parse(Path.join(dir, "a.zsh"), "if [[ -n $x ]] { print ${(U)x} }\n")
  end

  test "GDScript that does not parse is refused", %{tmp_dir: dir} do
    assert {:error, "not parseable: " <> why} =
             Lang.parse(Path.join(dir, "a.gd"), "extends Node\n\nfunc _ready(:\n\tpass\n")

    assert why =~ "line 3"
    assert :ok = Lang.parse(Path.join(dir, "a.gd"), "extends Node\n\nfunc _ready():\n\tpass\n")
  end

  test "gdformat formats a GDScript file in its style at HEAD", %{tmp_dir: dir} do
    repo(dir, [{"a.gd", "extends Node\n\n\nfunc f():\n\tvar x = 1\n\tprint(x)\n"}])
    assert {:ok, _} = edit(dir, [%{file: "a.gd", old: "var x = 1", new: "var  x=2"}])
    assert File.read!(Path.join(dir, "a.gd")) == "extends Node\n\n\nfunc f():\n\tvar x = 2\n\tprint(x)\n"
  end

  test "gdlint is on the lines changed, not the debt around them", %{tmp_dir: dir} do
    repo(dir, [{"a.gd", "extends Node\n\n\nfunc BadOne():\n\tpass\n\n\nfunc fine():\n\tpass\n"}])

    assert {:ok, %{changed: [%{lint: [found]}]}} =
             edit(dir, [%{file: "a.gd", old: "func fine():", new: "func AlsoBad():"}])

    assert %{kind: "gdlint", at: "a.gd:8", message: "Function name \"AlsoBad\" is not valid (function-name)"} =
             found
  end

  test "TOML that does not parse is refused", %{tmp_dir: dir} do
    assert {:error, "not parseable: " <> why} = Lang.parse(Path.join(dir, "a.toml"), "a = 1\n[t\nb = 2\n")
    assert why =~ "invalid TOML"
    assert :ok = Lang.parse(Path.join(dir, "a.toml"), "[t]\nb = 2\n")
  end

  test "taplo formats a TOML file in its style at HEAD", %{tmp_dir: dir} do
    repo(dir, [{"a.toml", "[t]\nb = 2\n"}])
    assert {:ok, _} = edit(dir, [%{file: "a.toml", old: "b = 2", new: "b   =   [1,2]"}])
    assert File.read!(Path.join(dir, "a.toml")) == "[t]\nb = [1, 2]\n"
  end

  test "JSON that does not parse is refused; a tsconfig's comments are its own", %{tmp_dir: dir} do
    assert {:error, "not parseable: " <> why} = Lang.parse(Path.join(dir, "a.json"), ~s({"a": 1,}\n))
    assert why =~ "Expected a property"
    assert :ok = Lang.parse(Path.join(dir, "a.json"), ~s({"a": 1}\n))
    assert :ok = Lang.parse(Path.join(dir, "tsconfig.json"), ~s({\n  // why\n  "a": 1\n}\n))
    assert :ok = Lang.parse(Path.join(dir, "a.jsonc"), ~s({\n  // why\n  "a": 1\n}\n))
  end

  test "biome formats a JSON file in its style at HEAD", %{tmp_dir: dir} do
    repo(dir, [{"a.json", ~s({ "a": 1 }\n)}])
    assert {:ok, _} = edit(dir, [%{file: "a.json", old: ~s("a": 1), new: ~s("a":2)}])
    assert File.read!(Path.join(dir, "a.json")) == ~s({ "a": 2 }\n)
  end

  test "Lua that does not parse is refused", %{tmp_dir: dir} do
    assert {:error, "not parseable: " <> _} = Lang.parse(Path.join(dir, "a.lua"), "x = (\n")
    assert :ok = Lang.parse(Path.join(dir, "a.lua"), "x = 1\n")
  end

  test "stylua formats a Lua file in its style at HEAD", %{tmp_dir: dir} do
    repo(dir, [{"a.lua", "local x = 1\n"}])
    assert {:ok, _} = edit(dir, [%{file: "a.lua", old: "local x = 1", new: "local x=2"}])
    assert File.read!(Path.join(dir, "a.lua")) == "local x = 2\n"
  end

  test "an undefined name in Nix is refused, by the parse check", %{tmp_dir: dir} do
    repo(dir, [{"a.nix", "{ pkgs }: { a = pkgs.hello; }\n"}])

    assert {:error, why} = edit(dir, [%{file: "a.nix", old: "pkgs.hello", new: "pkgz.hello"}])
    assert why =~ "undefined variable 'pkgz'"
  end

  test "nil names an unused binding on a line changed, which the parse check and statix do not", %{
    tmp_dir: dir
  } do
    repo(dir, [{"a.nix", "{ pkgs }: { a = pkgs.hello; }\n"}])

    # line 4, once nixfmt has laid the `let` out
    assert {:ok, %{changed: [%{lint: [%{kind: "nil", at: "a.nix:4", message: "Unused binding"}]}]}} =
             edit(dir, [%{file: "a.nix", old: "a = pkgs.hello", new: "a = let x = 1; in pkgs.hello"}])
  end

  test "Zig that does not parse is refused; an unused local is not, being a change half made", %{
    tmp_dir: dir
  } do
    assert {:error, "not parseable: " <> why} = Lang.parse(Path.join(dir, "a.zig"), "pub fn f( {\n")
    assert why =~ "expected type expression"
    assert :ok = Lang.parse(Path.join(dir, "a.zig"), "pub fn f() void {\n    const x = 1;\n}\n")
  end

  test "zig fmt formats a Zig file in its style at HEAD", %{tmp_dir: dir} do
    repo(dir, [{"a.zig", "pub fn f() u8 {\n    return 1;\n}\n"}])
    assert {:ok, _} = edit(dir, [%{file: "a.zig", old: "    return 1;", new: "  return   2;"}])
    assert File.read!(Path.join(dir, "a.zig")) == "pub fn f() u8 {\n    return 2;\n}\n"
  end

  test "zig ast-check names an unused local on a line changed, not the debt around it", %{tmp_dir: dir} do
    repo(dir, [{"a.zig", "pub fn f() void {\n    const a = 1;\n    _ = 2;\n}\n"}])

    assert {:ok, %{changed: [%{lint: [found]}]}} =
             edit(dir, [%{file: "a.zig", old: "    _ = 2;", new: "    const b = 2;"}])

    assert %{kind: "zig", at: "a.zig:3", message: "unused local constant"} = found
  end

  test "TypeScript that does not parse is refused", %{tmp_dir: dir} do
    assert {:error, "not parseable: " <> why} = Lang.parse(Path.join(dir, "a.ts"), "function f( {\n")
    assert why =~ "parse"
    assert :ok = Lang.parse(Path.join(dir, "a.tsx"), "export const A = () => <div />;\n")
  end

  test "a biome.json this biome cannot read refuses nothing that parses", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "biome.json"), ~s({"organizeImports": {"enabled": true}}\n))
    assert :ok = Lang.parse(Path.join(dir, "a.ts"), "const a = 1;\n")
  end

  test "biome formats a TypeScript file in its style at HEAD", %{tmp_dir: dir} do
    repo(dir, [{"a.ts", "export const a = { b: 1 };\n"}])
    assert {:ok, _} = edit(dir, [%{file: "a.ts", old: "{ b: 1 }", new: "{b:2}"}])
    assert File.read!(Path.join(dir, "a.ts")) == "export const a = { b: 2 };\n"
  end

  test "a new TypeScript file is formatted only where the repo has a biome config", %{tmp_dir: dir} do
    repo(dir, [{"other", ""}])
    assert Lang.format(Path.join(dir, "a.ts"), "const a = 1\n") == "const a = 1\n"

    File.write!(Path.join(dir, "biome.json"), "{}\n")
    assert Lang.format(Path.join(dir, "a.ts"), "const a = 1\n") == "const a = 1;\n"
  end

  test "biome lints the lines changed, not the debt around them", %{tmp_dir: dir} do
    repo(dir, [{"a.ts", "const a = 1;\nexport const b = 2;\n"}])

    assert {:ok, %{changed: [%{lint: [found]}]}} =
             edit(dir, [%{file: "a.ts", old: "export const b = 2;", new: "const b = 2;"}])

    assert %{kind: "biome", at: "a.ts:2", message: "noUnusedVariables: " <> _} = found
  end

  test "Python that does not parse is refused", %{tmp_dir: dir} do
    assert {:error, "not parseable: " <> why} = Lang.parse(Path.join(dir, "a.py"), "def f( :\n    return 1\n")
    assert why =~ "a.py:1:8: Expected a parameter"
    assert :ok = Lang.parse(Path.join(dir, "a.py"), "def f():\n    return 1\n")
  end

  test "ruff formats a Python file in its style at HEAD; a new one only where the repo has a ruff.toml", %{
    tmp_dir: dir
  } do
    repo(dir, [{"a.py", "def f(a, b):\n    return a + b\n"}])
    assert {:ok, _} = edit(dir, [%{file: "a.py", old: "return a + b", new: "return a+b+1"}])
    assert File.read!(Path.join(dir, "a.py")) == "def f(a, b):\n    return a + b + 1\n"

    assert Lang.format(Path.join(dir, "b.py"), "x=1\n") == "x=1\n"
    File.write!(Path.join(dir, "ruff.toml"), "")
    assert Lang.format(Path.join(dir, "b.py"), "x=1\n") == "x = 1\n"
  end

  test "ruff lints the lines changed, not the debt around them", %{tmp_dir: dir} do
    repo(dir, [{"a.py", "import os\n\n\ndef f():\n    return 1\n"}])

    assert {:ok, %{changed: [%{lint: [found]}]}} =
             edit(dir, [%{file: "a.py", old: "    return 1", new: "    x = 2\n    return 1"}])

    assert %{kind: "ruff", at: "a.py:5", message: "F841: Local variable `x` is assigned to but never used"} =
             found
  end

  test "Go that does not parse is refused, and gofmt formats what does", %{tmp_dir: dir} do
    assert {:error, "not parseable: " <> why} =
             Lang.parse(Path.join(dir, "a.go"), "package main\nfunc f( {\n}\n")

    assert why =~ "2:9: expected ')'"

    repo(dir, [{"a.go", "package main\n\nfunc f() int {\n\treturn 1\n}\n"}])
    assert {:ok, _} = edit(dir, [%{file: "a.go", old: "\treturn 1", new: "return   2"}])
    assert File.read!(Path.join(dir, "a.go")) == "package main\n\nfunc f() int {\n\treturn 2\n}\n"
  end

  test "Rust that does not parse is refused; an async fn and a let chain are no older edition's", %{
    tmp_dir: dir
  } do
    assert {:error, "not parseable: " <> why} = Lang.parse(Path.join(dir, "a.rs"), "fn f( {\n}\n")
    assert why =~ "unclosed delimiter"

    chain = "async fn f(a: Option<u8>) {\n    if let Some(x) = a && x > 1 {}\n}\n"
    assert :ok = Lang.parse(Path.join(dir, "a.rs"), chain)
  end

  test "rustfmt formats a Rust file in its style at HEAD", %{tmp_dir: dir} do
    repo(dir, [{"a.rs", "fn f() -> u8 {\n    1\n}\n"}])
    assert {:ok, _} = edit(dir, [%{file: "a.rs", old: "    1\n", new: "  1+1\n"}])
    assert File.read!(Path.join(dir, "a.rs")) == "fn f() -> u8 {\n    1 + 1\n}\n"
  end

  test "a file that did not parse before the edit is not refused for it", %{tmp_dir: dir} do
    commented = "{\n  // why\n  \"a\": 1\n}\n"
    repo(dir, [{"a.json", commented}])

    assert {:ok, _} = edit(dir, [%{file: "a.json", old: ~s("a": 1), new: ~s("a": 2)}])
    assert File.read!(Path.join(dir, "a.json")) == String.replace(commented, "1", "2")
  end

  test "a file with no row is written as it is", %{tmp_dir: dir} do
    refute Lang.known?("a.txt")
    assert {:ok, _} = edit(dir, [%{file: "a.txt", old: "", new: "{ not json"}])
  end

  if System.find_executable("yamlfmt") do
    test "yamlfmt: YAML that does not parse is refused, and a file in its style at HEAD is formatted", %{
      tmp_dir: dir
    } do
      assert {:error, "not parseable: " <> why} =
               Lang.parse(Path.join(dir, "a.yaml"), "a: 1\nb:\n  - x\n - y\n")

      assert why =~ "line 3"

      repo(dir, [{"a.yml", "a: 1\nb:\n  - x\n"}])
      assert {:ok, _} = edit(dir, [%{file: "a.yml", old: "a: 1", new: "a:    2"}])
      assert File.read!(Path.join(dir, "a.yml")) == "a: 2\nb:\n  - x\n"
    end

    test "yamlfmt: a template that was never YAML is edited as it is", %{tmp_dir: dir} do
      helm = "name: {{ .Values.name }}\n{{- if .Values.on }}\non: true\n{{- end }}\n"
      repo(dir, [{"a.yaml", helm}])

      assert {:ok, _} = edit(dir, [%{file: "a.yaml", old: "on: true", new: "on: false"}])
      assert File.read!(Path.join(dir, "a.yaml")) == String.replace(helm, "true", "false")
    end
  end

  if System.find_executable("csharpier") do
    test "csharpier: C# that does not parse is refused, and a file in its style at HEAD is formatted" do
      # csharpier skips what a .gitignore above the file names, and menard's names the test's tmp_dir
      dir = Path.join(System.tmp_dir!(), "menard-lang-#{System.pid()}-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:error, "not parseable: " <> why} =
               Lang.parse(Path.join(dir, "A.cs"), "class A {\n  void F( {\n}\n")

      assert why =~ "CS1026"

      repo(dir, [{"A.cs", "class A\n{\n    void F()\n    {\n        var x = 1;\n    }\n}\n"}])
      assert {:ok, _} = edit(dir, [%{file: "A.cs", old: "var x = 1;", new: "var x=2;"}])
      assert File.read!(Path.join(dir, "A.cs")) =~ "        var x = 2;\n"
    end
  end

  if System.find_executable("nixfmt") do
    test "nixfmt: formats a file in its style at HEAD", %{tmp_dir: dir} do
      repo(dir, [{"a.nix", "{\n  a = 1;\n}\n"}])
      assert {:ok, _} = edit(dir, [%{file: "a.nix", old: "a = 1;", new: "a   =   2;"}])
      assert File.read!(Path.join(dir, "a.nix")) == "{\n  a = 2;\n}\n"
    end
  end

  if System.find_executable("statix") do
    test "statix: lint on the lines changed", %{tmp_dir: dir} do
      repo(dir, [{"a.nix", "{\n  a = (1);\n  b = 2;\n}\n"}])

      assert {:ok, %{changed: [%{lint: [found]}]}} =
               edit(dir, [%{file: "a.nix", old: "b = 2;", new: "b = (2);"}])

      assert %{kind: "statix", at: "a.nix:3"} = found
    end
  end
end
