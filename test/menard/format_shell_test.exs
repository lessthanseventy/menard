defmodule Menard.FormatShellTest do
  # The shell fallback: a host whose plugins will not load here is formatted by its own `mix format`.
  # A fake `mix` on PATH stands in for it, and PATH is the VM's, so not async. The host sits outside
  # this checkout, whose .tool-versions would send the call through `mise exec` and past the fake.
  use ExUnit.Case, async: false

  setup do
    dir = Path.join(System.tmp_dir!(), "menard-shell-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "bin"))
    File.mkdir_p!(Path.join(dir, "host/lib"))

    File.write!(
      Path.join(dir, "host/.formatter.exs"),
      "[inputs: [\"lib/**/*.ex\"], plugins: [MenardNoSuchPlugin]]"
    )

    path = System.get_env("PATH")
    System.put_env("PATH", Path.join(dir, "bin") <> ":" <> path)

    on_exit(fn ->
      System.put_env("PATH", path)
      File.rm_rf!(dir)
    end)

    {:ok, dir: dir, target: Path.join(dir, "host/lib/a.ex")}
  end

  # `mix do loadpaths … + format FILE`: the file is its last argument
  defp fake_mix(dir, body) do
    mix = Path.join(dir, "bin/mix")
    File.write!(mix, "#!/usr/bin/env bash\nfile=\"${@: -1}\"\n" <> body)
    File.chmod!(mix, 0o755)
  end

  test "a host `mix format` out of time is stopped, not left to overwrite the file later", %{
    dir: dir,
    target: file
  } do
    fake_mix(dir, "sleep 2\necho '# late' > \"$file\"\n")

    assert {:error, message} = Menard.format_staged(file, "defmodule A do\nend\n", timeout: 1_000)
    assert message =~ "did not finish"

    Process.sleep(2_500)
    assert File.read!(file) == "defmodule A do\nend\n"
  end

  test "a format that finished leaves nothing in the caller's mailbox", %{dir: dir, target: file} do
    # the note of which formatter it waited on is for a timeout's reply; the MCP server is one
    # long-lived process, and every format through the fallback left one behind
    fake_mix(dir, "exit 0\n")

    assert {:ok, _formatted, nil} = Menard.format_staged(file, "defmodule A do\nend\n")
    refute_received {Menard, :waiting_on, _}
  end
end
