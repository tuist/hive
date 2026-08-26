defmodule HiveWeb.SitemapControllerTest do
  use HiveWeb.ConnCase, async: true

  use Mimic

  alias Hive.Auth
  alias Hive.Domains
  alias Hive.Projects

  test "lists public routes and excludes private resources", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    stub(Auth, :private?, fn -> false end)

    {:ok, public_project} =
      Projects.create_project(%{name: "Public project #{suffix}", visibility: :public})

    {:ok, private_project} =
      Projects.create_project(%{name: "Private project #{suffix}", visibility: :private})

    {:ok, public_domain} =
      Domains.create_domain(%{name: "Public domain #{suffix}", visibility: :public})

    {:ok, private_domain} =
      Domains.create_domain(%{name: "Private domain #{suffix}", visibility: :private})

    response =
      conn
      |> get(~p"/sitemap.xml")
      |> response(200)

    assert response =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
    assert response =~ "<loc>#{HiveWeb.Endpoint.url()}/</loc>"
    assert response =~ "<loc>#{HiveWeb.Endpoint.url()}/forage/feature-requests</loc>"
    assert response =~ "<loc>#{HiveWeb.Endpoint.url()}/projects/#{public_project.id}</loc>"
    assert response =~ "<loc>#{HiveWeb.Endpoint.url()}/domains/#{public_domain.id}</loc>"
    refute response =~ "/projects/#{private_project.id}"
    refute response =~ "/domains/#{private_domain.id}"
  end

  test "does not expose a sitemap for a private instance", %{conn: conn} do
    stub(Auth, :private?, fn -> true end)

    assert conn |> get(~p"/sitemap.xml") |> response(404) == "Not found"
  end
end
