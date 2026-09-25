# Vendored from github.com/bryanjos/diff (MIT, v1.1.0) — the Diffable protocol.
# Renamed from Diff.Diffable to Menard.Diff.Diffable so menard-as-a-library does not
# pollute the host's top-level namespace.

defprotocol Menard.Diff.Diffable do
  @moduledoc false
  def to_list(diffable)
end

defimpl Menard.Diff.Diffable, for: BitString do
  def to_list(diffable), do: String.graphemes(diffable)
end

defimpl Menard.Diff.Diffable, for: List do
  def to_list(diffable), do: diffable
end
