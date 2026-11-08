defmodule Menard.Test.HostFormat do
  @moduledoc false
  # A broken host project with a formatter of its own, and a plugin compiled into its _build: the
  # host_format tests', split into modules so their host VMs boot beside each other.

  def host(dir, formatter) do
    File.write!(Path.join(dir, "mix.exs"), "defmodule Broken.MixProject do\n  this does not parse (\n")
    File.write!(Path.join(dir, ".formatter.exs"), formatter)
    File.mkdir_p!(Path.join(dir, "lib"))
    dir
  end

  def write(dir, name, code) do
    file = Path.join([dir, "lib", name])
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, code)
    file
  end

  # A plugin compiled into `root`'s _build, as a host's last build would hold it. `body` is its
  # format/2, with `contents` and `opts` bound.
  def plug(root, name, body) do
    plugin = :"Elixir.MenardTest#{name}#{System.unique_integer([:positive])}"
    ebin = Path.join(root, "_build/dev/lib/plug/ebin")
    File.mkdir_p!(ebin)

    [{^plugin, beam}] =
      Code.compile_string("""
      defmodule #{inspect(plugin)} do
        @behaviour Mix.Tasks.Format
        def features(_opts), do: [extensions: [".ex"]]

        def format(contents, opts) do
          _ = opts
          #{body}
        end
      end
      """)

    :code.purge(plugin)
    :code.delete(plugin)
    File.write!(Path.join(ebin, "#{plugin}.beam"), beam)
    plugin
  end
end
