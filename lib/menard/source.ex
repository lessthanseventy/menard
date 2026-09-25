defmodule Menard.Source do
  @moduledoc false

  @doc """
  The dotted name an `{:__aliases__, _, parts}` spells. `__MODULE__` is an AST node, not an atom,
  so it becomes `current` when the enclosing module is known and stays `__MODULE__` when not.
  """
  def alias_name(parts, current \\ nil) do
    Enum.map_join(parts, ".", fn
      {:__MODULE__, _meta, _ctx} -> current || "__MODULE__"
      part -> to_string(part)
    end)
  end
end
