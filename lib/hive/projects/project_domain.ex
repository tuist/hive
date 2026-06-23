defmodule Hive.Projects.ProjectDomain do
  @moduledoc false

  use Ecto.Schema

  alias Hive.Domains.Domain
  alias Hive.Projects.Project

  @primary_key false
  @foreign_key_type :binary_id

  schema "projects_domains" do
    belongs_to :project, Project, primary_key: true
    belongs_to :domain, Domain, primary_key: true

    timestamps(type: :utc_datetime)
  end
end
