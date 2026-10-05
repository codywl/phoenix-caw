defmodule Cah.CahServer do
  use GenServer
  alias Phoenix.PubSub

  @topic "cah:game"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def join(player_id, pid, name) do
    GenServer.call(__MODULE__, {:join, player_id, pid, name})
  end

  def leave(player_id) do
    GenServer.cast(__MODULE__, {:leave, player_id})
  end

  def game_state do
    GenServer.call(__MODULE__, :game_state)
  end

  def reconnect(player_id, pid) do
    GenServer.call(__MODULE__, {:reconnect, player_id, pid})
  end

  def start_game(player) do
    GenServer.call(__MODULE__, {:start_game, player})
  end

  def submit(player_id, cards) do
    GenServer.call(__MODULE__, {:submit, player_id, cards})
  end

  def pick_cards(player_id, index) do
    GenServer.call(__MODULE__, {:pick_cards, player_id, index})
  end

  @impl true
  def init(_) do
    {:ok,
     %{
       host: nil,
       phase: :lobby,
       players: %{},
       monitors: %{},
       white_deck: Cah.Cards.deal_white(),
       black_deck: Cah.Cards.deal_black(),
       black_card: nil,
       discard: [],
       submissions: %{},
       czar: nil,
       reveal_order: [],
       player_order: [],
       target_score: 5
     }}
  end

  @impl true
  def handle_call({:submit, player_id, cards}, _, state) do
    player = Map.get(state.players, player_id)

    cond do
      player == nil ->
        {:reply, {:error, :no_player}, state}

      state.phase != :submitting ->
        {:reply, {:error, :wrong_phase}, state}

      length(cards) != state.black_card.picks ->
        {:reply, {:error, :invalid_card_count}, state}

      length(Enum.uniq(cards)) != length(cards) ->
        {:reply, {:error, :duplicate_whites}, state}

      not Enum.all?(cards, &(&1 in player.hand)) ->
        {:reply, {:error, :not_in_hand}, state}

      Map.has_key?(state.submissions, player_id) ->
        {:reply, {:error, :already_submitted}, state}

      true ->
        remaining_cards = player.hand -- cards

        players =
          Map.update!(state.players, player_id, fn player ->
            %{player | hand: remaining_cards}
          end)

        submissions = Map.put_new(state.submissions, player_id, cards)

        state = %{state | players: players, submissions: submissions}
        state = maybe_progress(state)

        broadcast_state(state)
        send_hand(state, player_id)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:start_game, player_id}, _, state) do
    is_host = state.host == player_id
    has_enough_players = map_size(state.players) > 2

    cond do
      is_host and has_enough_players ->
        state =
          Enum.reduce(Map.keys(state.players), state, fn id, state ->
            draw(state, id, 10)
          end)

        [black_card | rest] = state.black_deck
        black_card = %{id: black_card, picks: Cah.Cards.black_spaces(black_card)}

        czar = Enum.random(Map.keys(state.players))

        state = %{
          state
          | black_card: black_card,
            black_deck: rest,
            phase: :submitting,
            czar: czar
        }

        broadcast_state(state)
        {:reply, :ok, state}

      is_host ->
        {:reply, {:error, :insufficient_players}, state}

      true ->
        {:reply, {:error, :not_host}, state}
    end
  end

  @impl true
  def handle_call({:reconnect, player_id, pid}, _, state) do
    if Map.has_key?(state.players, player_id) do
      {role, state} = attach(state, player_id, pid)
      {:reply, {:ok, role}, state}
    else
      {:reply, :error, state}
    end
  end

  @impl true
  def handle_call({:join, player_id, pid, name}, _, state) do
    is_new? = not Map.has_key?(state.players, player_id)

    players =
      Map.put_new(state.players, player_id, %{
        name: name,
        pid: nil,
        connected: false,
        hand: [],
        score: 0
      })

    player_order = if is_new?, do: state.player_order ++ [player_id], else: state.player_order
    state = %{state | players: players, player_order: player_order}

    {role, state} = attach(state, player_id, pid)
    {:reply, {:ok, role}, state}
  end

  @impl true
  def handle_call(:game_state, _, state) do
    {:reply, public_state(state), state}
  end

  @impl true
  def handle_call({:pick_cards, player_id, index}, _, state) do
    cond do
      state.czar != player_id ->
        {:reply, {:error, :player_not_czar}, state}

      state.phase != :judging ->
        {:reply, {:error, :incorrect_phase}, state}

      index < 0 or index >= length(state.reveal_order) ->
        {:reply, {:error, :index_oob}, state}

      true ->
        winner_id = Enum.at(state.reveal_order, index)

        players =
          Map.update!(state.players, winner_id, fn player ->
            %{player | score: player.score + 1}
          end)

        discard = state.discard ++ (state.submissions |> Map.values() |> List.flatten())

        state = %{state | players: players, discard: discard}

        state =
          if state.players[winner_id].score >= state.target_score do
            %{state | phase: :ended}
          else
            next_round(state)
          end

        broadcast_state(state)
        {:reply, :ok, state}
    end
  end

  defp next_round(state) do
    state =
      if state.black_deck == [] do
        %{state | black_deck: Cah.Cards.deal_black()}
      else
        state
      end

    [black_card | rest] = state.black_deck
    black_card = %{id: black_card, picks: Cah.Cards.black_spaces(black_card)}

    state =
      Enum.reduce(Map.keys(state.players), state, fn id, state ->
        player = Map.get(state.players, id)
        draw(state, id, 10 - length(player.hand))
      end)

    current_czar = Enum.find_index(state.player_order, &(&1 == state.czar))
    new_czar = Enum.at(state.player_order, rem(current_czar + 1, length(state.player_order)))

    %{
      state
      | submissions: %{},
        reveal_order: [],
        czar: new_czar,
        black_card: black_card,
        black_deck: rest,
        phase: :submitting
    }
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    {player_id, monitors} = Map.pop(state.monitors, ref)
    state = %{state | monitors: monitors}

    state =
      case state.players[player_id] do
        %{pid: ^pid} -> put_in(state, [:players, player_id, :connected], false)
        _ -> state
      end

    broadcast_state(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:leave, player_id}, state) do
    {:noreply, remove_player(state, player_id)}
  end

  defp maybe_progress(state) do
    expected_size = Enum.count(state.players, fn {id, p} -> p.connected and id != state.czar end)

    if expected_size == map_size(state.submissions) do
      reveal_order = state.submissions |> Map.keys() |> Enum.shuffle()
      %{state | phase: :judging, reveal_order: reveal_order}
    else
      state
    end
  end

  defp send_hand(state, player_id) do
    case Map.get(state.players, player_id) do
      %{pid: pid, hand: hand} when is_pid(pid) -> send(pid, {:hand, hand})
      _ -> :ok
    end
  end

  defp draw(state, player_id, n) do
    state =
      if length(state.white_deck) < n do
        %{state | white_deck: state.white_deck ++ Enum.shuffle(state.discard), discard: []}
      else
        state
      end

    {drawn_cards, rest} = Enum.split(state.white_deck, n)

    players =
      Map.update!(state.players, player_id, fn player ->
        %{player | hand: player.hand ++ drawn_cards}
      end)

    state = %{state | players: players, white_deck: rest}
    send_hand(state, player_id)
    state
  end

  # Common logic for :join, :reconnect signals
  defp attach(state, player_id, pid) do
    players =
      Map.update!(state.players, player_id, fn player -> %{player | pid: pid, connected: true} end)

    host = state.host || player_id
    role = if host == player_id, do: :host, else: :player
    ref = Process.monitor(pid)
    monitors = Map.put(state.monitors, ref, player_id)
    state = %{state | players: players, monitors: monitors, host: host}

    broadcast_state(state)
    send_hand(state, player_id)
    {role, state}
  end

  defp remove_player(state, player_id) do
    %{
      state
      | players: Map.delete(state.players, player_id),
        player_order: List.delete(state.player_order, player_id)
    }
    |> tap(&broadcast_state/1)
  end

  defp broadcast_state(state) do
    PubSub.broadcast(
      :cah_pubsub,
      @topic,
      {:game_state, public_state(state)}
    )
  end

  defp public_state(state) do
    players =
      Enum.map(state.player_order, fn id ->
        player = state.players[id]

        %{
          id: id,
          name: player.name,
          connected: player.connected,
          submitted: Map.has_key?(state.submissions, id)
        }
      end)

    lobby_phase = state.phase
    black_card = state.black_card
    czar = state.czar

    submissions =
      if state.phase in [:judging, :reveal] do
        Enum.map(state.reveal_order, &state.submissions[&1])
      else
        []
      end

    %{
      players: players,
      phase: lobby_phase,
      black_card: black_card,
      czar: czar,
      submissions: submissions
    }
  end
end
