defmodule AnyLogin.MixProject do
  use Mix.Project

  def project do
    [
      app: :any_login,
      version: "0.1.0",
      elixir: "~> 1.20",
      description: "A generator for development-only Phoenix account switching",
      source_url: "https://github.com/higakijin/any_login",
      package: package(),
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.2"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/higakijin/any_login"},
      files: ~w(assets lib test .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [main: "readme", extras: ["README.md"]]
  end
end
