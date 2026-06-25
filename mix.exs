defmodule Hive.MixProject do
  use Mix.Project

  def project do
    [
      app: :hive,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [
      mod: {Hive.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.4"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0", override: true},
      {:jason, "~> 1.2"},
      {:flop, "~> 0.26"},
      {:let_me, "~> 3.0"},
      {:mdex, "~> 0.13"},
      {:lumis, "~> 0.1"},
      {:noora, "~> 0.82"},
      {:req, "~> 0.5"},
      {:ex_aws_auth, "~> 1.3"},
      {:carta, "~> 0.2.0"},
      {:browse_chrome, "~> 0.4.0"},
      {:browse, "~> 0.5.0", override: true},
      {:muontrap, "~> 1.7", override: true},
      {:ueberauth, "~> 0.10"},
      {:ueberauth_oidcc, "~> 0.4"},
      {:ueberauth_github, "~> 0.8"},
      {:emcp, "~> 0.3.4"},
      {:boruta, git: "https://github.com/malach-it/boruta_auth", branch: "master"},
      {:condukt, github: "tuist/condukt", tag: "1.7.0", override: true},
      {:oban, "~> 2.23"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:saxy, "~> 1.5"},
      {:sentry, "~> 13.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.7", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["compile", "esbuild hive"],
      "assets.deploy": [
        "esbuild hive --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo",
        "test"
      ]
    ]
  end
end
