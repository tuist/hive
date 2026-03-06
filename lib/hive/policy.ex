defmodule Hive.Policy do
  use LetMe.Policy, check_module: Hive.Policy.Checks

  object :dashboard do
    action :write do
      allow :authenticated
    end

    action :read do
      allow true
    end
  end
end
