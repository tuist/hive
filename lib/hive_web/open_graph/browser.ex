defmodule HiveWeb.OpenGraph.Browser do
  @moduledoc false

  @behaviour Browse.Browser

  alias HiveWeb.OpenGraph.Browser.Manager

  @call_timeout 30_000
  @default_delegate BrowseChrome.Browser

  @impl Browse.Browser
  def init(opts) do
    Manager.start_link(Keyword.put_new(opts, :delegate, @default_delegate))
  end

  @impl Browse.Browser
  def terminate(reason, manager) do
    Manager.stop(manager, reason)
    :ok
  catch
    :exit, _reason -> :ok
  end

  @impl Browse.Browser
  def navigate(manager, url, opts), do: call(manager, :navigate, [url, opts])

  @impl Browse.Browser
  def current_url(manager), do: call(manager, :current_url, [])

  @impl Browse.Browser
  def content(manager), do: call(manager, :content, [])

  @impl Browse.Browser
  def evaluate(manager, script, opts), do: call(manager, :evaluate, [script, opts])

  @impl Browse.Browser
  def capture_screenshot(manager, opts), do: call(manager, :capture_screenshot, [opts])

  @impl Browse.Browser
  def set_viewport(manager, width, height, opts),
    do: call(manager, :set_viewport, [width, height, opts])

  @impl Browse.Browser
  def print_to_pdf(manager, opts), do: call(manager, :print_to_pdf, [opts])

  @impl Browse.Browser
  def click(manager, locator, opts), do: call(manager, :click, [locator, opts])

  @impl Browse.Browser
  def fill(manager, locator, value, opts), do: call(manager, :fill, [locator, value, opts])

  @impl Browse.Browser
  def wait_for(manager, locator, opts), do: call(manager, :wait_for, [locator, opts])

  @impl Browse.Browser
  def go_back(manager, opts), do: call(manager, :go_back, [opts])

  @impl Browse.Browser
  def go_forward(manager, opts), do: call(manager, :go_forward, [opts])

  @impl Browse.Browser
  def reload(manager, opts), do: call(manager, :reload, [opts])

  @impl Browse.Browser
  def title(manager), do: call(manager, :title, [])

  @impl Browse.Browser
  def select_option(manager, locator, value, opts),
    do: call(manager, :select_option, [locator, value, opts])

  @impl Browse.Browser
  def hover(manager, locator, opts), do: call(manager, :hover, [locator, opts])

  @impl Browse.Browser
  def get_text(manager, locator, opts), do: call(manager, :get_text, [locator, opts])

  @impl Browse.Browser
  def get_attribute(manager, locator, name, opts),
    do: call(manager, :get_attribute, [locator, name, opts])

  @impl Browse.Browser
  def get_cookies(manager, opts), do: call(manager, :get_cookies, [opts])

  @impl Browse.Browser
  def set_cookie(manager, cookie, opts), do: call(manager, :set_cookie, [cookie, opts])

  @impl Browse.Browser
  def clear_cookies(manager, opts), do: call(manager, :clear_cookies, [opts])

  defp call(manager, operation, args) do
    GenServer.call(manager, {:operation, operation, args}, @call_timeout)
  catch
    :exit, _reason -> {:error, :browser_unavailable}
  end
end

defmodule HiveWeb.OpenGraph.Browser.Manager do
  @moduledoc false

  use GenServer

  def start_link(opts) do
    {delegate, opts} = Keyword.pop!(opts, :delegate)
    opts = Keyword.delete(opts, :name)

    GenServer.start_link(__MODULE__, {delegate, opts})
  end

  def stop(manager, reason) do
    GenServer.call(manager, {:stop, reason}, 30_000)
  end

  @impl GenServer
  def init({delegate, opts}) do
    Process.flag(:trap_exit, true)
    {:ok, %{browser: :not_started, delegate: delegate, opts: opts}}
  end

  @impl GenServer
  def handle_call({:operation, operation, args}, _from, state) do
    case ensure_browser(state) do
      {:ok, browser, state} ->
        result = apply(state.delegate, operation, [browser | args])
        {:reply, result, maybe_reset_browser(result, state)}

      {:error, reason, state} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:stop, reason}, _from, state) do
    {:stop, :normal, :ok, terminate_browser(reason, state)}
  end

  @impl GenServer
  def handle_info({:EXIT, browser, _reason}, %{browser: {:started, browser}} = state) do
    {:noreply, %{state | browser: :not_started}}
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  @impl GenServer
  def terminate(reason, %{browser: {:started, browser}, delegate: delegate}) do
    delegate.terminate(reason, browser)
  end

  def terminate(_reason, _state), do: :ok

  defp ensure_browser(%{browser: {:started, browser}} = state) do
    {:ok, browser, state}
  end

  defp ensure_browser(%{browser: :not_started, delegate: delegate, opts: opts} = state) do
    case delegate.init(opts) do
      {:ok, browser} -> {:ok, browser, %{state | browser: {:started, browser}}}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp maybe_reset_browser({:error, :browser_unavailable}, state),
    do: %{state | browser: :not_started}

  defp maybe_reset_browser(_result, state), do: state

  defp terminate_browser(reason, %{browser: {:started, browser}, delegate: delegate} = state) do
    delegate.terminate(reason, browser)
    %{state | browser: :not_started}
  end

  defp terminate_browser(_reason, state), do: state
end
