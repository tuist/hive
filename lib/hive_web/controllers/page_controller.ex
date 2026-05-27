defmodule HiveWeb.PageController do
  use HiveWeb, :controller

  def home(conn, _params) do
    html(conn, """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Hive</title>
        <link rel="stylesheet" href="/assets/js/app.css">
      </head>
      <body>
        <main>
          <h1>Hive</h1>
          <p>Product work orchestration for Tuist.</p>
        </main>
      </body>
    </html>
    """)
  end
end
