defmodule HiveWeb.Api.V1.Schemas do
  @moduledoc false

  defmodule Error do
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "Error",
      type: :object,
      properties: %{
        error: %Schema{type: :string},
        error_description: %Schema{type: :string}
      },
      required: [:error]
    })
  end

  defmodule Domain do
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "Domain",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string}
      },
      required: [:id, :name]
    })
  end

  defmodule Pagination do
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "Pagination",
      type: :object,
      properties: %{
        page: %Schema{type: :integer, minimum: 1},
        page_size: %Schema{type: :integer, minimum: 1},
        total_count: %Schema{type: :integer, minimum: 0},
        total_pages: %Schema{type: :integer, minimum: 0}
      },
      required: [:page, :page_size, :total_count, :total_pages]
    })
  end

  defmodule User do
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "User",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        email: %Schema{type: :string, format: :email},
        name: %Schema{type: :string, nullable: true},
        role: %Schema{type: :string, enum: ["collaborator", "member", "admin"]}
      },
      required: [:id, :email, :role]
    })
  end

  defmodule UserResponse do
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "UserResponse",
      type: :object,
      properties: %{data: User},
      required: [:data]
    })
  end

  defmodule ForageItem do
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "ForageItem",
      type: :object,
      properties: %{
        id: %Schema{type: :string},
        type: %Schema{type: :string},
        title: %Schema{type: :string},
        body: %Schema{type: :string, nullable: true},
        status: %Schema{type: :string},
        visibility: %Schema{type: :string, nullable: true},
        source_label: %Schema{type: :string, nullable: true},
        external_label: %Schema{type: :string, nullable: true},
        external_url: %Schema{type: :string, format: :uri, nullable: true},
        occurred_at: %Schema{type: :string, format: :"date-time", nullable: true},
        updated_at: %Schema{type: :string, format: :"date-time"},
        domains: %Schema{type: :array, items: Domain}
      },
      required: [:id, :type, :title, :status, :updated_at, :domains]
    })
  end

  defmodule ForageListResponse do
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "ForageListResponse",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: ForageItem},
        pagination: Pagination
      },
      required: [:data, :pagination]
    })
  end

  defmodule ForageItemResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ForageItemResponse",
      type: :object,
      properties: %{data: ForageItem},
      required: [:data]
    })
  end

  defmodule Spec do
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "Spec",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        number: %Schema{type: :integer, minimum: 1},
        title: %Schema{type: :string},
        summary: %Schema{type: :string, nullable: true},
        body: %Schema{type: :string},
        status: %Schema{type: :string},
        visibility: %Schema{type: :string, enum: ["public", "private"]},
        revision: %Schema{type: :integer, minimum: 1},
        has_new_activity: %Schema{type: :boolean},
        updated_at: %Schema{type: :string, format: :"date-time"},
        domains: %Schema{type: :array, items: Domain}
      },
      required: [
        :id,
        :number,
        :title,
        :body,
        :status,
        :visibility,
        :revision,
        :has_new_activity,
        :updated_at,
        :domains
      ]
    })
  end

  defmodule SpecListResponse do
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "SpecListResponse",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: Spec},
        pagination: Pagination
      },
      required: [:data, :pagination]
    })
  end

  defmodule SpecResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SpecResponse",
      type: :object,
      properties: %{data: Spec},
      required: [:data]
    })
  end

  defmodule Drop do
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "Drop",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        number: %Schema{type: :integer, minimum: 1},
        title: %Schema{type: :string},
        body: %Schema{type: :string, nullable: true},
        source_type: %Schema{type: :string, enum: ["github_release", "rss"]},
        version: %Schema{type: :string, nullable: true},
        url: %Schema{type: :string, format: :uri},
        published_at: %Schema{type: :string, format: :"date-time", nullable: true},
        domains: %Schema{type: :array, items: Domain}
      },
      required: [:id, :number, :title, :source_type, :url, :domains]
    })
  end

  defmodule DropListResponse do
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "DropListResponse",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: Drop},
        pagination: Pagination
      },
      required: [:data, :pagination]
    })
  end

  defmodule DropResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "DropResponse",
      type: :object,
      properties: %{data: Drop},
      required: [:data]
    })
  end

  defmodule DropDigest do
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "DropDigest",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        week_start: %Schema{type: :string, format: :date},
        week_end: %Schema{type: :string, format: :date},
        title: %Schema{type: :string},
        summary: %Schema{type: :string},
        body: %Schema{type: :string},
        drop_count: %Schema{type: :integer, minimum: 0},
        published_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [
        :id,
        :week_start,
        :week_end,
        :title,
        :summary,
        :body,
        :drop_count,
        :published_at
      ]
    })
  end

  defmodule DropDigestListResponse do
    require OpenApiSpex
    alias OpenApiSpex.Schema

    OpenApiSpex.schema(%{
      title: "DropDigestListResponse",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: DropDigest},
        pagination: Pagination
      },
      required: [:data, :pagination]
    })
  end

  defmodule DropDigestResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "DropDigestResponse",
      type: :object,
      properties: %{data: DropDigest},
      required: [:data]
    })
  end
end
