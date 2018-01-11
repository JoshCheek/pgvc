defmodule JoshTest.Mixfile do
  use Mix.Project

  def project do
    [
      app: :josh_test,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps(),
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      applications: [:ecto, :postgrex],
      extra_applications: [:logger],
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 2.2"},
      {:postgrex, ">= 0.0.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
    ]
  end
end
