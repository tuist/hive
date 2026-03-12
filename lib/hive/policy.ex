defmodule Hive.Policy do
  use LetMe.Policy, check_module: Hive.Policy.Checks

  object :signal, Hive.Signals.Signal do
    action :read do
      allow(true)
    end
  end

  object :swarm do
    action :read do
      allow(true)
    end
  end

  object :instance do
    action :read do
      allow(:authenticated)
    end

    action :write do
      allow(:authenticated)
    end
  end

  object :slack_integration, Hive.Integrations.SlackIntegration do
    action :read do
      allow(:authenticated)
    end

    action :write do
      allow(:authenticated)
    end
  end

  object :slack_channel, Hive.Integrations.SlackChannel do
    action :read do
      allow(:authenticated)
    end

    action :write do
      allow(:authenticated)
    end
  end

  object :github_app, Hive.Integrations.GitHubApp do
    action :read do
      allow(:authenticated)
    end

    action :write do
      allow(:authenticated)
    end
  end

  object :github_repository, Hive.Integrations.GitHubRepository do
    action :read do
      allow(:authenticated)
    end

    action :write do
      allow(:authenticated)
    end
  end
end
