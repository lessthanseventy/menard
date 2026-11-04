defmodule Menard.Lang do
  @moduledoc """
  What a write does for a language that is not Elixir, one row per extension: a parse check that
  refuses, a formatter, a linter on the lines changed. A tool that is not installed is skipped.

  The formatter leaves alone a file not in its style at HEAD: one line's edit must not rewrite a
  whole file of someone else's style (ficciones holds no `nixfmt`-style Nix).
  """

  @shell %{
    parse: ~w(bash -n),
    format: ~w(shfmt --filename FILE),
    lint: ~w(shellcheck -f json -)
  }

  @tools %{
    ".nix" => %{
      parse: ~w(nix-instantiate --parse -),
      format: ~w(nixfmt -),
      lint: ~w(statix check -s -o json)
    },
    ".sh" => @shell,
    ".bash" => @shell
  }

  @doc "Whether `file` has a row."
  @spec known?(String.t()) :: boolean()
  def known?(file), do: is_map_key(@tools, Path.extname(file))

  @doc "`:ok`, or why `code` is not written to `file`: it does not parse."
  @spec parse(String.t(), String.t()) :: :ok | {:error, String.t()}
  def parse(file, code) do
    with %{parse: argv} <- @tools[Path.extname(file)],
         {out, status} when status != 0 <- tool(argv, file, code, ~s(2>&1 >/dev/null)) do
      {:error, "not parseable: #{String.trim(out)}"}
    else
      _ -> :ok
    end
  end

  @doc "`code` through `file`'s formatter, or as it is: the file is not in its style at HEAD."
  @spec format(String.t(), String.t()) :: String.t()
  def format(file, code) do
    with %{format: argv} <- @tools[Path.extname(file)],
         true <- in_style?(argv, file),
         {out, 0} <- tool(argv, file, code) do
      out
    else
      _ -> code
    end
  end

  @doc """
  What `file`'s linter finds on it as it is on disk, on the lines changed since the last commit:
  `kind`, `message`, `at`, as a run verb's failures.
  """
  @spec lint(String.t()) :: [map()]
  def lint(file) do
    with %{lint: [exe | _] = argv} <- @tools[Path.extname(file)],
         {out, _status} <- tool(argv, file, File.read!(file)),
         [_ | _] = issues <- issues(exe, out, Path.basename(file)) do
      dir = Path.dirname(file)
      for i <- Menard.Run.only_changed(issues, dir), do: %{i | at: Path.join(dir, i.at)}
    else
      _ -> []
    end
  end

  defp in_style?(argv, file) do
    dir = Path.dirname(file)

    case System.cmd("git", ["-C", dir, "rev-parse", "--is-inside-work-tree"], stderr_to_stdout: true) do
      {_inside, 0} ->
        case System.cmd("git", ["-C", dir, "show", "HEAD:./#{Path.basename(file)}"], stderr_to_stdout: true) do
          {was, 0} -> tool(argv, file, was) == {was, 0}
          # not at HEAD: new, and no one's style yet
          _new -> true
        end

      # no history to say whose style it is
      _outside ->
        false
    end
  end

  defp issues("shellcheck", out, base) do
    case JSON.decode(out) do
      {:ok, found} when is_list(found) ->
        for %{"line" => line, "code" => code, "message" => message} <- found,
            do: %{kind: "shellcheck", message: "SC#{code}: #{message}", at: "#{base}:#{line}"}

      _ ->
        []
    end
  end

  defp issues("statix", out, base) do
    case JSON.decode(out) do
      {:ok, %{"report" => report}} ->
        for %{"diagnostics" => diagnostics} <- report,
            %{"at" => %{"from" => %{"line" => line}}, "message" => message} <- diagnostics,
            do: %{kind: "statix", message: message, at: "#{base}:#{line}"}

      _ ->
        []
    end
  end

  # `code` on the tool's stdin, as the file it will be; nil where the tool is not installed. Beside
  # the file, for the config it reads from there (.editorconfig, statix.toml).
  defp tool([exe | _] = argv, file, code, redirect \\ "2>/dev/null") do
    if System.find_executable(exe) do
      input =
        Path.join(System.tmp_dir!(), "menard-lang-#{System.pid()}-#{System.unique_integer([:positive])}")

      argv = Enum.map(argv, &if(&1 == "FILE", do: Path.expand(file), else: &1))
      dir = Path.dirname(Path.expand(file))
      cd = if File.dir?(dir), do: dir, else: System.tmp_dir!()
      File.write!(input, code)

      try do
        System.cmd("sh", ["-c", ~s(exec "$@" <"$0" #{redirect}), input | argv], cd: cd)
      after
        File.rm(input)
      end
    end
  end
end
