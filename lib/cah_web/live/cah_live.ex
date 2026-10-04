defmodule CahWeb.CahLive do
  use CahWeb, :live_view
  alias Phoenix.PubSub
  alias Cah.CahServer

  @topic "cah:game"
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

      <%= if @phase == :submitting do %>
        <span>playing</span>
        <div>
          {Cah.Cards.text(@black_card.id)}
        </div>
        <ul>
          <li
            :for={card <- @hand}
            phx-click="select_card"
            phx-value-card={Cah.Cards.id(card)}
            class="cah-card"
          >
            {Cah.Cards.text(card)}
          </li>
        </ul>
        <button phx-click="submit_cards">Submit</button>
      <% end %>

      <%= if @phase == :judging do %>
        <h1>judging phase</h1>
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

    %{players: players, phase: phase, black_card: black_card, czar: czar} = CahServer.game_state()

    {:ok,
     assign(socket,
       player_id: player_id,
       role: role,
       players: players,
       phase: phase,
       hand: [],
       black_card: black_card,
       czar: czar,
       selected: []
     )}
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
  def handle_event("select_card", %{"card" => card_id}, socket) do
    case Integer.parse(card_id) do
      {int, _} ->
        card = {:white, int}

        selected =
          cond do
            card in socket.assigns.selected ->
              List.delete(socket.assigns.selected, card)

            length(socket.assigns.selected) < socket.assigns.black_card.picks ->
              socket.assigns.selected ++ [card]

            true ->
              socket.assigns.selected
          end

        {:noreply, assign(socket, selected: selected)}

      :error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("submit_cards", _params, socket) do
    CahServer.submit(socket.assigns.player_id, socket.assigns.selected)
    {:noreply, assign(socket, selected: [])}
  end

  @impl true
  def handle_info(
        {:game_state,
         %{:players => players, :phase => phase, :black_card => black_card, :czar => czar}},
        socket
      ) do
    {:noreply, assign(socket, players: players, phase: phase, black_card: black_card, czar: czar)}
  end

  @impl true
  def handle_info({:hand, hand}, socket) do
    {:noreply, assign(socket, hand: hand)}
  end
end
