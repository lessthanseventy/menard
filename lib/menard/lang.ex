defmodule Menard.Lang do
  @moduledoc """
  What a write does for a language that is not Elixir, one row per extension, or per shebang where a
  script has none: a parse check that refuses, a formatter, linters on the lines changed. A tool
  that is not installed is skipped, and `missing/2` says which.

  The formatter leaves alone a file not in its style at HEAD: one line's edit must not rewrite a
  whole file of someone else's style.
  """

  alias Menard.Run.Lint

  # shellcheck on the file, not its stdin, so `-x` follows what it sources beside it (lib.sh of the
  # hooks): the sourced file's variables are assigned, and SC1091 "not following" is not said
  @shell %{
    parse: ~w(bash -n),
    format: ~w(shfmt --filename FILE),
    lint: [~w(shellcheck -f json -x -P SCRIPTDIR FILE)]
  }

  @tools %{
    ".nix" => %{
      parse: ~w(nix-instantiate --parse -),
      format: ~w(nixfmt -),
      lint: [~w(statix check -s -o json), ~w(nil diagnostics -- -)]
    },
    ".lua" => %{parse: ~w(luac -p -), format: ~w(stylua -), lint: []},
    ".sh" => @shell,
    ".bash" => @shell
  }

  @doc "The extensions with a row."
  @spec extensions() :: [String.t()]
  def extensions, do: Map.keys(@tools)

  @doc """
  Whether `file` has a row, going by `code` where its name does not say, or by what is on disk.
  """
  @spec known?(String.t(), String.t() | nil) :: boolean()
  def known?(file, code \\ nil), do: row(file, code) != nil

  @doc "`file`'s tools that are not installed, each skipped."
  @spec missing(String.t(), String.t() | nil) :: [String.t()]
  def missing(file, code \\ nil) do
    case row(file, code) do
      nil ->
        []

      row ->
        for [exe | _] <- [row.parse, row.format | row.lint], !System.find_executable(exe), uniq: true, do: exe
    end
  end

  @doc "`:ok`, or why `code` is not written to `file`: it does not parse."
  @spec parse(String.t(), String.t()) :: :ok | {:error, String.t()}
  def parse(file, code) do
    with %{parse: argv} <- row(file, code),
         {out, status} when status != 0 <- tool(argv, file, code, ~s(2>&1 >/dev/null)) do
      {:error, "not parseable: #{String.trim(out)}"}
    else
      _ -> :ok
    end
  end

  @doc "`code` through `file`'s formatter, or as it is: the file is not in its style at HEAD."
  @spec format(String.t(), String.t()) :: String.t()
  def format(file, code) do
    with %{format: [exe | _] = argv} <- row(file, code),
         true <- System.find_executable(exe) != nil,
         true <- in_style?(argv, file),
         {out, 0} <- tool(argv, file, code) do
      out
    else
      _ -> code
    end
  end

  @doc """
  What `file`'s linters find on it as it is on disk, on the lines changed since the last commit:
  `kind`, `message`, `at`, as a run verb's failures.
  """
  @spec lint(String.t()) :: [map()]
  def lint(file) do
    code = File.read!(file)
    base = Path.basename(file)

    issues =
      for [exe | _] = argv <- (row(file, code) || %{lint: []}).lint,
          {out, _status} <- List.wrap(tool(argv, file, code)),
          issue <- issues(exe, out, base),
          do: issue

    if issues == [] do
      []
    else
      dir = Path.dirname(file)
      for i <- Lint.only_changed(issues, dir), do: %{i | at: Path.join(dir, i.at)}
    end
  end

  # a script says what it is in its first line: a `.sh` of zsh's does not parse under bash, and is
  # no row's; one with no extension has a row only by this
  defp row(file, code) do
    case {Path.extname(file), shebang(file, code)} do
      {".sh", other} when other in ~w(zsh fish ksh) -> nil
      {".bash", other} when other in ~w(zsh fish ksh) -> nil
      {"", shell} when shell in ~w(bash sh dash) -> @shell
      {extension, _shell} -> @tools[extension]
    end
  end

  # only where the name leaves it open: an Elixir file goes through here on every write
  defp shebang(file, code) do
    with true <- Path.extname(file) in ["", ".sh", ".bash"],
         code when is_binary(code) <- code || read(file),
         [_, shell] <-
           Regex.run(~r/\A#!\s*(?:\S*\/)?(?:env\s+(?:-\S+\s+)*)?(bash|dash|zsh|fish|ksh|sh)(?:\s|$)/, code) do
      shell
    else
      _ -> nil
    end
  end

  defp read(file) do
    case File.read(file) do
      {:ok, code} -> code
      _ -> nil
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
        # a followed file's findings are its own, not this file's at the same line numbers
        for %{"file" => file, "line" => line, "code" => code, "message" => message} <- found,
            Path.basename(file) == base,
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

  # What is unused, which neither the parse check nor statix says: nil's errors are what the parse
  # check has refused already, and its other warnings statix's. Its output is for humans, with no
  # other format: a line it no longer matches is a finding unsaid, not a crash.
  defp issues("nil", out, base) do
    plain = String.replace(out, ~r/\e\[[0-9;]*m/, "")

    for [_, message, line] <- Regex.scan(~r/warning\[unused_\w+\]: (.+)\n\s*┌─ -:(\d+):/u, plain),
        do: %{kind: "nil", message: message, at: "#{base}:#{line}"}
  end

  # `code` on the tool's stdin, as the file it will be; nil where the tool is not installed. Beside
  # the file, for the config it reads from there (.editorconfig, statix.toml, stylua.toml).
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
