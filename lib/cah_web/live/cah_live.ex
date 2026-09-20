defmodule CahWeb.CahLive do
  use CahWeb, :live_view

  def render(assigns) do
    ~H"""
    <form phx-submit="join">
      <input type="text" name="player_name" />
      <.button type="submit">Join</.button>
    </form>

    <ul>
      <li :for={player <- @players}>{player}</li>
    </ul>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, players: [])}
  end

  def handle_event("join", %{"player_name" => player_name}, socket) do
    {:noreply, assign(socket, players: socket.assigns.players ++ [player_name])}
  end
end
