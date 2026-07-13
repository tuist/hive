defmodule Hive.Agents.Tools.FetchUrlContentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Hive.Agents.Tools.FetchUrlContent

  test "extracts the main page content without repeated site chrome" do
    stub(Req, :run, fn request ->
      response =
        Req.Response.new(
          status: 200,
          headers: [{"content-type", "text/html"}],
          body: """
          <html>
            <head><title>Release details</title></head>
            <body>
              <header>Repeated navigation and account controls</header>
              <main>
                <h1>Shipped improvement</h1>
                <p>The cache now warms before the first build.</p>
              </main>
              <footer>Repeated legal and navigation links</footer>
            </body>
          </html>
          """
        )

      {request, response}
    end)

    assert {:ok, result} = FetchUrlContent.fetch("https://example.com/release")
    assert result.title == "Release details"
    assert result.content =~ "Shipped improvement"
    assert result.content =~ "The cache now warms before the first build."
    refute result.content =~ "Repeated navigation"
    refute result.content =~ "Repeated legal"
  end

  test "falls back to the complete page when no main element exists" do
    stub(Req, :run, fn request ->
      response =
        Req.Response.new(
          status: 200,
          headers: [{"content-type", "text/html"}],
          body: "<html><body><p>Standalone release evidence</p></body></html>"
        )

      {request, response}
    end)

    assert {:ok, result} = FetchUrlContent.fetch("https://example.com/release")
    assert result.content == "Standalone release evidence"
  end
end
