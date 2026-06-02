defmodule Hive.Forage.FeatureRequestTest do
  use ExUnit.Case, async: true

  alias Hive.Forage.FeatureRequest

  defp changeset(attrs), do: FeatureRequest.changeset(%FeatureRequest{}, attrs)

  describe "changeset/2" do
    test "is valid with a title and description" do
      changeset = changeset(%{"title" => "A title", "description" => "Long enough description."})

      assert changeset.valid?
    end

    test "requires a title and a description" do
      changeset = changeset(%{})

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:title]
      assert {"can't be blank", _} = changeset.errors[:description]
    end

    test "rejects a title longer than 160 characters" do
      changeset =
        changeset(%{"title" => String.duplicate("a", 161), "description" => "Long enough."})

      refute changeset.valid?
      assert {"should be at most %{count} character(s)", _} = changeset.errors[:title]
    end

    test "rejects a description shorter than 10 characters" do
      changeset = changeset(%{"title" => "A title", "description" => "short"})

      refute changeset.valid?
      assert {"should be at least %{count} character(s)", _} = changeset.errors[:description]
    end

    test "always forces status to open and visibility to public" do
      changeset =
        changeset(%{
          "title" => "A title",
          "description" => "Long enough description.",
          "status" => "closed",
          "visibility" => "organization"
        })

      assert Ecto.Changeset.get_field(changeset, :status) == :open
      assert Ecto.Changeset.get_field(changeset, :visibility) == :public
    end
  end
end
