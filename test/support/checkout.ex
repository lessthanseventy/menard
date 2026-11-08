defmodule Menard.Test.Checkout do
  @moduledoc false
  # A copy of this checkout for bin/menard to build and break in: the bin_copy tests, one module
  # each so their cold compiles run beside each other.
  import ExUnit.Assertions, only: [flunk: 1]

  @root Path.expand("../..", __DIR__)

  # this checkout's tracked files, its deps and its dev build, at DIR/menard
  def checkout_copy!(dir) do
    copy = tracked_copy!(dir, "menard")

    # one OS process each, not File.cp_r!: thousands of files through the VM's one file server,
    # four copies at once, stalled every other test's File.cwd!/File.regular? for a minute
    File.mkdir_p!(Path.join(copy, "_build"))
    {_, 0} = System.cmd("cp", ["-a", Path.join(@root, "deps"), Path.join(copy, "deps")])
    {_, 0} = System.cmd("cp", ["-a", Path.join(@root, "_build/dev"), Path.join(copy, "_build/dev")])
    copy
  end

  # this checkout's tracked files alone, a fresh install's, at DIR/NAME
  def tracked_copy!(dir, name) do
    copy = Path.join(dir, name)
    {files, 0} = System.cmd("git", ["-C", @root, "ls-files"])

    for f <- String.split(files, "\n", trim: true) do
      File.mkdir_p!(Path.dirname(Path.join(copy, f)))
      src = Path.join(@root, f)

      # a tracked symlink is a link in the copy too (eval's desk-tdd links desk's dirs: cp! refuses one)
      case File.read_link(src) do
        {:ok, target} -> File.ln_s!(target, Path.join(copy, f))
        {:error, _} -> copy_tracked!(src, Path.join(copy, f), f)
      end
    end

    copy
  end

  # a tracked file not there: a rebase or checkout in flight in this checkout (a second session's:
  # 2026-10-01, bin/menard itself, once in a full gate) rewrites files one by one. Named, not a
  # bare :enoent at the copy's first verb
  defp copy_tracked!(src, dest, f) do
    case File.cp(src, dest) do
      :ok ->
        :ok

      {:error, why} ->
        flunk(
          "#{f} is tracked and could not be copied (#{why}): a git operation rewriting this checkout while the suite runs?"
        )
    end
  end
end
