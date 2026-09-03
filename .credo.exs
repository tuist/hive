%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "priv/repo/migrations/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      requires: ["credo/checks/**/*.ex"],
      checks: %{
        extra: [
          # Match the nesting policy the sibling `../tuist/server`
          # repo uses. Two levels is stricter than most Elixir
          # projects and forces awkward extraction on straight
          # `if enabled?() do case ... do` blocks the domain
          # layer relies on for cheap early-return guards.
          {Credo.Check.Refactor.Nesting, [max_nesting: 3]},
          {Hive.Credo.Checks.TimestampsType,
           files: %{included: ["priv/repo/migrations/"]}, allowed_type: :utc_datetime},
          {Hive.Credo.Checks.TimestampsType,
           files: %{included: ["lib/"]}, allowed_type: :utc_datetime},
          {Hive.Credo.Checks.RepoCallInEnum, []}
        ]
      }
    }
  ]
}
