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

  object :integration do
    action :read do
      allow(:authenticated)
    end

    action :write do
      allow(:authenticated)
    end
  end
end
