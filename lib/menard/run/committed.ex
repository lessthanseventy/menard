defmodule Menard.Run.Committed do
  @moduledoc """
  `run … --committed`: the project's last commit, checked out in a git worktree menard keeps in its
  cache, for a run that must not read a working tree being edited under it. The worktree is the
  project's own from one run to the next, so its `_build` stays warm; the project's `deps` are linked
  in, not fetched again.
  """

  @doc """
  The worktree of `dir`'s repository at HEAD, under `kept`: `dir`'s own path in it, the commit, and
  how many paths of the working tree differ from it (what this run does not see). What an earlier
  run wrote there is discarded.
  """
  @spec at_head(String.t(), String.t()) ::
          {:ok, %{dir: String.t(), sha: String.t(), uncommitted: non_neg_integer()}} | {:error, String.t()}
  def at_head(dir, kept \\ Path.join(Menard.cache_dir(), "committed")) do
    dir = Path.expand(dir)

    with {:ok, top} <- git(dir, ~w(rev-parse --show-toplevel)),
         {:ok, below} <- git(dir, ~w(rev-parse --show-prefix)),
         {:ok, sha} <- git(dir, ~w(rev-parse --short HEAD)),
         {:ok, changed} <- git(dir, ~w(status --porcelain)),
         tree = Path.join(kept, "#{Path.basename(top)}-#{:erlang.phash2(top)}"),
         {:ok, _} <- placed(top, tree, sha) do
      at = Path.expand(below, tree)
      deps = Path.join(dir, "deps")
      if File.dir?(deps), do: File.ln_s(deps, Path.join(at, "deps"))
      {:ok, %{dir: at, sha: sha, uncommitted: changed |> String.split("\n", trim: true) |> length()}}
    else
      {:error, said} ->
        {:error, "--committed runs the last commit, in a git worktree menard keeps: git said: #{said}"}
    end
  end

  defp placed(top, tree, sha) do
    if File.dir?(tree) do
      with {:ok, _} <- git(tree, ["checkout", "--detach", "--force", "-q", sha]),
           do: git(tree, ~w(clean -fdq))
    else
      File.mkdir_p!(Path.dirname(tree))
      # a worktree whose directory was removed is still on git's list until pruned
      with {:ok, _} <- git(top, ~w(worktree prune)),
           do: git(top, ["worktree", "add", "--detach", "-q", tree, sha])
    end
  end

  defp git(dir, args) do
    case System.cmd("git", ["-C", dir | args], stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, _status} -> {:error, String.trim(out)}
    end
  end
end
