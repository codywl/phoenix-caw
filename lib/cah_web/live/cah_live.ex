defmodule CahWeb.CahLive do
  use CahWeb, :live_view
  alias Phoenix.PubSub
  alias Cah.CahServer

  @topic "cah:game"
  # things needed:
  # players
  # cards for players
  # tracking card czar
  # tracking score
  # deciding win score
  # passing control to players
  @impl true
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

  @impl true
  def mount(_params, _session, socket) do
    PubSub.subscribe(:cah_pubsub, @topic)
    {:ok, role} = CahServer.join(self())
    {:ok, assign(socket, players: [])}
  end

  @impl true
  def handle_event("join", %{"player_name" => player_name}, socket) do
    PubSub.broadcast(:cah_pubsub, @topic, {:user_update, %{name: player_name}})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:user_update, %{name: player_name}}, socket) do
    {:noreply, assign(socket, players: socket.assigns.players ++ [player_name])}
  end
end
