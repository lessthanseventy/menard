defmodule Menard.Test.Edits do
  @moduledoc false
  # `edit` as both doors call it, and a read back: the edit tests', in modules that run beside
  # each other.

  alias Menard.Verbs

  # as both doors call it: `then` runs in `Menard.Verbs.call/2`
  def edit(dir, edits, more \\ %{}), do: Verbs.call(Verbs.Edit, Map.merge(%{root: dir, edits: edits}, more))

  def read(dir, file), do: File.read!(Path.join(dir, file))
end
