defmodule CahWeb.CahLive do
  use CahWeb, :live_view
  alias Phoenix.PubSub
  alias Cah.CahServer
  alias Phoenix.LiveView.JS

  @topic "cah:game"
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <link href="https://cdn.jsdelivr.net/npm/daisyui@5" rel="stylesheet" type="text/css" />
    <div class="flex flex-col md:flex-row h-screen">
      <aside class="shadow shadow-4 md:w-64 h-auto md:h-full shrink-0 border-r border-base-300 bg-base-200 p-4 overflow-y-auto">
        <h2 class="text-lg font-bold mb-2">Players</h2>

        <div class="divider"></div>

        <ul class="space-y-2">
          <li :for={player <- @players} class="flex items-center gap-2">
            <div :if={not player.connected} class="status status-error animate-ping" />
            <div :if={player.connected} class="status status-info" />
            <span class="truncate">
              {player.name}
              <span class="text-sm opacity-60">({player.score})</span>
              {if not player.connected, do: " (disconnected)"}
            </span>
          </li>
          <%= if @czar != nil do %>
            <span class="block border border-slate-700 rounded my-4 p-2">
              {Enum.find(assigns.players, &(&1.id == @czar)).name} is the Card Czar.
            </span>
          <% end %>
        </ul>
      </aside>

      <main class="flex flex-col items-center md:items-start flex-1 min-w-0 p-6 overflow-y-auto">
        <%= if @phase != :ended do %>
          <%= if @role == nil do %>
            <div class="self-center rounded p-4 border border-slate-700">
              <h1 class="text-2xl text-bold my-2">Crows Against World</h1>
              <form class="flex gap-1" phx-submit="join">
                <input type="text" class="input" name="player_name" placeholder="Player name" />
                <button class="btn" type="submit">Join</button>
              </form>
            </div>
          <% end %>

          <%= if @role == :host and @phase == :lobby do %>
            <div class="self-center w-full md:w-96 flex flex-col rounded p-4 my-2 border border-slate-700">
              <h1 class="text-xl py-4">You're the host.</h1>
              <div class="divider" />
              <span class="mb-2 text-sm">Controls</span>
              <div class="flex gap-2">
                <form phx-submit="start">
                  <.button>Start Game</.button>
                </form>
                <form phx-submit="host_leave">
                  <.button>Leave Game</.button>
                </form>
              </div>
            </div>
          <% end %>

          <%= if @role != nil do %>
            <%= if length(@players) < 3 do %>
              <p class="self-center">
                Waiting for more players..
              </p>
            <% end %>

            <%= if length(@players) > 2 and @phase == :lobby do %>
              <p class="self-center">
                Waiting to start..
              </p>
            <% end %>
          <% end %>
          <%= if @phase == :judging do %>
            <div class="bg-black min-h-46 w-72 my-4 rounded">
              <h1 class="text-2xl text-white p-2">
                {Cah.Cards.text(@black_card.id)}
              </h1>
            </div>
            <div class="flex flex-col flex-wrap">
              <div :for={{cards, index} <- Enum.with_index(@submissions)} class="w-72">
                <div class="divider" />
                <div
                  class="stack stack-start w-full"
                  id={"submission-#{index}"}
                  phx-hook="CardStack"
                >
                  <span
                    :for={card <- cards}
                    class="stack-card border text-xl border-slate-700 rounded block bg-white w-full h-72 p-2 my-2 mr-2 text-black"
                  >
                    {Cah.Cards.text(card)}
                  </span>
                </div>
                <%= if @czar == @player_id do %>
                  <button
                    class="btn"
                    phx-click={@player_id == @czar && "pick_cards"}
                    phx-value-index={index}
                  >
                    Pick Cards
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>

          <%= if @phase == :submitting and @role != nil do %>
            <% me = get_self(assigns) %>
            <div class="bg-black h-46 w-72 my-4 p-2 rounded">
              <h1 class="text-2xl text-white p-2">
                {Cah.Cards.text(@black_card.id)}
              </h1>
            </div>

            <%= if @player_id != @czar and not (me.submitted or me.discarded) do %>
              <ul class="flex gap-4 overflow-x-auto md:overflow-visible md:flex-wrap max-w-full">
                <li
                  :for={card <- @hand}
                  class={["cah-card hover-3d shrink-0", card in @selected && "selected"]}
                >
                  <div class={[
                    "relative z-90 text-xl h-46 w-72 p-2 rounded-sm text-black",
                    (card in @selected && "bg-orange-400") || "bg-white"
                  ]}>
                    <%= case card do %>
                      <% {:blank, n} -> %>
                        <input
                          placeholder="Your text here.."
                          phx-keyup="blank_change"
                          class="z-100 rounded p-2"
                          phx-value-n={n}
                          phx-debounce="300"
                          value={Map.get(@blank_texts, n, "")}
                        />
                      <% _ -> %>
                        {Cah.Cards.text(card)}
                    <% end %>
                    <div
                      phx-click="select_card"
                      phx-value-card={Cah.Cards.id(card)}
                      class="select-none cursor-pointer flex justify-center items-center w-8 h-8 border-2 border-black rounded absolute right-2 bottom-2"
                    >
                      {(card in @selected && "x") || ""}
                    </div>
                  </div>
                </li>
                <div />
                <div />
                <div />
                <div />
                <div />
                <div />
                <div />
                <div />
              </ul>
              <button
                :if={length(@selected) == @black_card.picks}
                class="btn my-4"
                phx-click="submit_cards"
              >
                Submit Selected
              </button>
              <div class="tooltip" data-tip="Subtracts one point (unless at zero)">
                <button class="btn my-4" phx-click="discard_cards">Discard Selected</button>
              </div>
            <% else %>
              <%= if @player_id == @czar do %>
                Waiting for cards..
              <% else %>
                Waiting for other players..
              <% end %>
            <% end %>
          <% end %>
        <% else %>
          The game is over. The winner is {Enum.max_by(@players, & &1.score).name}.
          <ul>
            <li :for={player <- Enum.sort_by(@players, & &1.score, :desc)}>
              <span>{player.name} scored {player.score} points.</span>
            </li>
          </ul>
          <%= if @role == :host do %>
            <button phx-click="reset">Reset Game</button>
          <% end %>
        <% end %>
      </main>
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
      submissions: submissions,
      target_score: target_score,
      host: host
    } = CahServer.game_state()

    {:ok,
     assign(socket,
       player_id: player_id,
       role: role,
       players: players,
       phase: phase,
       hand: [],
       host: host,
       black_card: black_card,
       czar: czar,
       selected: [],
       submissions: submissions,
       target_score: target_score,
       blank_texts: %{}
     )}
  end

  @impl true
  def handle_event("reset", _params, socket) do
    case CahServer.reset_game(socket.assigns.player_id) do
      :ok -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, message_for(reason))}
    end
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
  def handle_event("host_leave", _params, socket) do
    case CahServer.leave(socket.assigns.player_id) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, message_for(reason))}
    end
  end

  @impl true
  def handle_event("blank_change", %{"n" => n, "value" => text}, socket) do
    case Integer.parse(n) do
      {int, _} ->
        blank_texts = Map.put(socket.assigns.blank_texts, int, text)
        {:noreply, assign(socket, blank_texts: blank_texts)}

      :error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_card", %{"card" => card_id}, socket) do
    case Cah.Cards.parse_id(card_id) do
      {:ok, card} ->
        selected =
          cond do
            card in socket.assigns.selected ->
              List.delete(socket.assigns.selected, card)

            # now we need to allow more cards than the black card picks for discarding purposes
            length(socket.assigns.selected) < 10 ->
              socket.assigns.selected ++ [card]

            true ->
              socket.assigns.selected
          end

        {:noreply, assign(socket, selected: selected)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("submit_cards", _params, socket) do
    case CahServer.submit(
           socket.assigns.player_id,
           socket.assigns.selected,
           socket.assigns.blank_texts
         ) do
      :ok ->
        {:noreply, assign(socket, selected: [], blank_texts: %{})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, message_for(reason))}
    end
  end

  @impl true
  def handle_event("discard_cards", _params, socket) do
    case CahServer.discard(
           socket.assigns.player_id,
           socket.assigns.selected
         ) do
      :ok ->
        {:noreply, assign(socket, selected: [], blank_texts: %{})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, message_for(reason))}
    end
  end

  @impl true
  def handle_event("pick_cards", %{"index" => index}, socket) do
    case Integer.parse(index) do
      {int, _} ->
        case CahServer.pick_cards(socket.assigns.player_id, int) do
          :ok ->
            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, message_for(reason))}
        end

      :error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:notice, reason}, socket) do
    {:noreply, put_flash(socket, :info, message_for(reason))}
  end

  @impl true
  def handle_info(
        {:game_state,
         %{
           :players => players,
           :phase => phase,
           :black_card => black_card,
           :czar => czar,
           :submissions => submissions,
           :target_score => target_score,
           :host => host
         }},
        socket
      ) do
    role =
      cond do
        not Enum.any?(players, &(&1.id == socket.assigns.player_id)) -> nil
        host == socket.assigns.player_id -> :host
        true -> :player
      end

    {:noreply,
     assign(socket,
       players: players,
       role: role,
       phase: phase,
       black_card: black_card,
       czar: czar,
       submissions: submissions,
       target_score: target_score
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

      :player_not_czar ->
        "You're not the Card Czar."

      :incorrect_phase ->
        "This isn't the right game phase."

      :index_oob ->
        "The player index is out of bounds."

      :no_player ->
        "You don't appear to be a player."

      :wrong_phase ->
        "You can't submit in this phase."

      :invalid_card_count ->
        "The number of cards is wrong."

      :duplicate_whites ->
        "There are duplicate white cards."

      :not_in_hand ->
        "Cards were submitted that aren't in the player hand."

      :already_submitted ->
        "Already submitted."

      :already_discarded ->
        "Already discarded."

      :too_many_discards ->
        "There are too many discards."

      :no_cards ->
        "No cards found."

      :czar_dropped ->
        "The Card Czar player dropped; moving on to next round."

      :not_enough_players_left ->
        "There are no longer enough players to play the game. Resetting."

      :invalid_blank_text ->
        "The blank card text is empty or too long."

      :too_many_players_discarding ->
        "Too many players discarding - moving on to next round."

      :cannot_remove_not_existing ->
        "Could not remove a non-existent player."

      _ ->
        "Something went wrong."
    end
  end

  defp get_self(assigns) do
    Enum.find(assigns.players, &(&1.id == assigns.player_id))
  end
end
