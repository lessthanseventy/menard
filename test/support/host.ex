defmodule Menard.Test.Host do
  @moduledoc false
  # A throwaway host project for the verbs that run the host's mix: the least mix.exs that is one.

  @doc "Write a mix.exs for `app` into `dir`, its module named after it (`:held` is Held.MixProject)."
  def mix_project(dir, app) do
    File.write!(Path.join(dir, "mix.exs"), """
    defmodule #{Macro.camelize(to_string(app))}.MixProject do
      use Mix.Project
      def project, do: [app: #{inspect(app)}, version: "0.1.0"]
    end
    """)
  end
end
