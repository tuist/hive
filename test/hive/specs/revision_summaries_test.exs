defmodule Hive.Specs.RevisionSummariesTest do
  use ExUnit.Case, async: true

  alias Hive.Specs.Revision
  alias Hive.Specs.RevisionSummaries

  test "describes the initial revision without a model request" do
    revision = %Revision{revision: 1, status: :draft}

    assert RevisionSummaries.describe(revision, nil) ==
             "Created the initial draft proposal."
  end

  test "describes meaningful body changes from line counts" do
    previous = %Revision{
      revision: 1,
      title: "GitHub sign-in",
      status: :draft,
      body: "Keep source URL visible.\nImport comments."
    }

    revision = %Revision{
      revision: 2,
      title: "GitHub sign-in",
      status: :draft,
      body: "Keep source URL visible.\nImport discussion comments.\nSkip duplicates."
    }

    assert RevisionSummaries.describe(revision, previous) ==
             "Updated the proposal body with 2 additions and 1 removal."
  end

  test "combines title, status, and body changes" do
    previous = %Revision{
      revision: 1,
      title: "Sign-in",
      status: :draft,
      body: "Initial proposal."
    }

    revision = %Revision{
      revision: 2,
      title: "GitHub sign-in",
      status: :in_review,
      body: "Initial proposal.\nAdd token refresh behavior."
    }

    assert RevisionSummaries.describe(revision, previous) ==
             "Renamed the spec, moved the status from draft to in review and expanded the proposal body with 1 addition."
  end

  test "reports revisions without proposal changes" do
    previous = %Revision{revision: 1, title: "Sign-in", status: :draft, body: "Proposal."}
    revision = %Revision{revision: 2, title: "Sign-in", status: :draft, body: "Proposal."}

    assert RevisionSummaries.describe(revision, previous) ==
             "Saved the revision without changing the proposal text."
  end
end
