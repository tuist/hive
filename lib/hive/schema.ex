defmodule Hive.Schema do
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      @primary_key {:id, Hive.UUIDv7, autogenerate: true}
      @foreign_key_type Hive.UUIDv7
    end
  end
end
