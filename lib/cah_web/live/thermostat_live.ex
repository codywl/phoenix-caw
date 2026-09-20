defmodule CahWeb.ThermostatLive do
  use CahWeb, :live_view

  def render(assigns) do
    ~H"""
    Current temperature: {@temperature}°F <button phx-click="inc-temperature">+</button>
    """
  end

  def mount(_params, _session, socket) do
    temperature = 70
    {:ok, assign(socket, :temperature, temperature)}
  end

  def handle_event("inc-temperature", params, socket) do
    IO.inspect(socket.assigns)
    IO.inspect(params)
    {:noreply, update(socket, :temperature, &(&1 + 1))}
  end
end
