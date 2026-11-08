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

  test "a script with no extension has a row by its shebang, and a .sh of zsh's has none", %{tmp_dir: dir} do
    assert {:error, "not parseable" <> _} =
             Lang.parse(Path.join(dir, "run"), "#!/usr/bin/env bash\nif true; then\n")

    assert Lang.known?("bin/x", "#!/bin/sh\n")
    assert :ok = Lang.parse(Path.join(dir, "notes"), "if true; then\n")
    refute Lang.known?("bin/y", "#!/usr/local/sh/python\n")

    # zsh's own syntax, which bash -n refuses
    zsh = "#!/bin/zsh\nfor i ({1..3}) echo $i\n"
    refute Lang.known?("a.sh", zsh)
    assert :ok = Lang.parse(Path.join(dir, "a.sh"), zsh)
    refute Lang.known?("bin/z", "#!/usr/bin/env zsh\n")
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

  test "a file with no row is written as it is", %{tmp_dir: dir} do
    refute Lang.known?("a.json")
    assert {:ok, _} = edit(dir, [%{file: "a.json", old: "", new: "{ not json"}])
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
