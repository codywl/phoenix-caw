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
    <link href="https://cdn.jsdelivr.net/npm/daisyui@5" rel="stylesheet" type="text/css" />
    <Layouts.flash_group flash={@flash} />
    <div class="main-content max-w-96 p-4">
      <ul class="">
        <h2>Players</h2>
        <div class="divider"></div>
        <li :for={player <- @players}>{player.name}</li>
      </ul>
      <%= if @role == nil do %>
        <form phx-submit="join">
          <input type="text" class="input" name="player_name" placeholder="Player name" />
        </form>
      <% end %>

      <%= if @role == :host and @phase == :lobby do %>
        <form phx-submit="start">
          <.button>Start Game</.button>
        </form>
      <% end %>

      <%= if @phase == :judging do %>
        submitted cards
        <div :for={{cards, index} <- Enum.with_index(@submissions)}>
          <button phx-click={@player_id == @czar && "pick_cards"} phx-value-index={index}>
            <span :for={card <- cards}>{Cah.Cards.text(card)}</span>
          </button>
        </div>
      <% end %>

      <%= if @phase == :submitting and @role != nil do %>
        <div>
          <h1 class="text-2xl my-4">
            {Cah.Cards.text(@black_card.id)}
          </h1>
        </div>
        <%= if @player_id != @czar and not get_self(assigns).submitted do %>
          <ul class="flex gap-2 flex-wrap w-screen">
            <li
              :for={card <- @hand}
              phx-click="select_card"
              phx-value-card={Cah.Cards.id(card)}
              class={["cah-card hover-3d", card in @selected && "selected"]}
            >
              <div class="text-xl h-46 w-72 p-2 rounded-sm bg-white text-black">
                {Cah.Cards.text(card)}
              </div>
              <div />
              <div />
              <div />
              <div />
              <div />
              <div />
              <div />
              <div />
            </li>
          </ul>
          <button class="btn my-4" phx-click="submit_cards">Submit Cards</button>
        <% else %>
          <%= if @player_id == @czar do %>
            Waiting for cards..
          <% else %>
            Waiting for other players..
          <% end %>
        <% end %>
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

    %{
      players: players,
      phase: phase,
      black_card: black_card,
      czar: czar,
      submissions: submissions
    } = CahServer.game_state()

    {:ok,
     assign(socket,
       player_id: player_id,
       role: role,
       players: players,
       phase: phase,
       hand: [],
       black_card: black_card,
       czar: czar,
       selected: [],
       submissions: submissions
     )}
  end

  @impl true
  def handle_event("join", %{"player_name" => player_name}, socket) do
    {:ok, role} = CahServer.join(socket.assigns.player_id, self(), player_name)
    {:noreply, assign(socket, role: role)}
  end

  @impl true
  def handle_event("start", _params, socket) do
    case CahServer.start_game(socket.assigns.player_id) do
      :ok -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, message_for(reason))}
    end
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
  def handle_event("pick_cards", %{"index" => index}, socket) do
    case Integer.parse(index) do
      {int, _} ->
        CahServer.pick_cards(socket.assigns.player_id, int)
        {:noreply, socket}

      :error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {:game_state,
         %{
           :players => players,
           :phase => phase,
           :black_card => black_card,
           :czar => czar,
           :submissions => submissions
         }},
        socket
      ) do
    role =
      if Enum.any?(players, &(&1.id == socket.assigns.player_id)),
        do: socket.assigns.role,
        else: nil

    {:noreply,
     assign(socket,
       players: players,
       role: role,
       phase: phase,
       black_card: black_card,
       czar: czar,
       submissions: submissions
     )}
  end

  @impl true
  def handle_info({:hand, hand}, socket) do
    {:noreply, assign(socket, hand: hand)}
  end

  defp message_for(reason) do
    case reason do
      :insufficient_players ->
        "You must have at least three players to play."

      :not_host ->
        "You aren't the host."

      _ ->
        "Something went wrong."
    end
  end

  defp get_self(assigns) do
    Enum.find(assigns.players, &(&1.id == assigns.player_id))
  end
end
