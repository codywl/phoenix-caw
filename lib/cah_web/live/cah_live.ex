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
    <div class="main-content max-w-96 p-4">
      <ul class="">
        <h2>Players</h2>
        <div class="divider"></div>
        <li :for={player <- @players}>{player.name}</li>
      </ul>
      <form phx-submit="join">
        <input type="text" class="input" name="player_name" placeholder="Player name" />
      </form>

      <%= if @role == :host and @phase == :lobby do %>
        <form phx-submit="start">
          <.button>Start Game</.button>
        </form>
      <% end %>

      <%= if @phase == :playing do %>
        <span>playing</span>
        <ul>
          <li :for={card <- @hand}>{Cah.Cards.text(card)}</li>
        </ul>
      <% end %>
    </div>
    """
  end

  @impl true
  # runs twice, once for the render and then again over the websocket
  # subscribes and reconnects (things that involve self()) only go into the second of those
  # since the first render and the second render both need players, CahServer.players() runs on both
  def mount(_params, %{"player_id" => player_id}, socket) do
    role =
      if connected?(socket) do
        PubSub.subscribe(:cah_pubsub, @topic)

        case CahServer.reconnect(player_id, self()) do
          {:ok, role} -> role
          :error -> nil
        end
      end

    %{players: players, phase: phase} = CahServer.game_state()

    {:ok,
     assign(socket, player_id: player_id, role: role, players: players, phase: phase, hand: [])}
  end

  @impl true
  def handle_event("join", %{"player_name" => player_name}, socket) do
    {:ok, role} = CahServer.join(socket.assigns.player_id, self(), player_name)
    {:noreply, assign(socket, role: role)}
  end

  @impl true
  def handle_event("start", _params, socket) do
    CahServer.start_game(socket.assigns.player_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:game_state, %{:players => players, :phase => phase}}, socket) do
    {:noreply, assign(socket, players: players, phase: phase)}
  end

  @impl true
  def handle_info({:hand, hand}, socket) do
    {:noreply, assign(socket, hand: hand)}
  end
end
