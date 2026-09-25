defmodule Menard.CallerDirTest do
  # Mutates the process environment, so not async.
  use ExUnit.Case, async: false

  setup do
    previous = System.get_env("MENARD_CWD")

    on_exit(fn ->
      if previous, do: System.put_env("MENARD_CWD", previous), else: System.delete_env("MENARD_CWD")
    end)
  end

  test "a relative path resolves against MENARD_CWD" do
    System.put_env("MENARD_CWD", "/somewhere/else")
    assert Menard.resolve("lib/a.ex") == "/somewhere/else/lib/a.ex"
  end

  test "bin/menard hands the caller's directory over as MENARD_CWD" do
    bin = Path.expand("../../bin/menard", __DIR__)
    assert File.read!(bin) =~ ~s(export MENARD_CWD=)
  end
end
