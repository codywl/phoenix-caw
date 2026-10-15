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
    GenServer.call(__MODULE__, {:leave, player_id})
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

  def reset_game(player_id) do
    GenServer.call(__MODULE__, {:reset_game, player_id})
  end

  def submit(player_id, cards, blank_texts) do
    GenServer.call(__MODULE__, {:submit, player_id, cards, blank_texts})
  end

  def discard(player_id, cards) do
    GenServer.call(__MODULE__, {:discard, player_id, cards})
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
       discarding: %{},
       submissions: %{},
       czar: nil,
       reveal_order: [],
       player_order: [],
       target_score: 5,
       grace_timers: %{},
       removal_timers: %{}
     }}
  end

  @impl true
  def handle_call({:submit, player_id, cards, blank_texts}, _, state) do
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

      Map.has_key?(state.discarding, player_id) ->
        {:reply, {:error, :already_discarded}, state}

      not Enum.all?(cards, fn
        {:blank, n} -> valid_blank_text?(Map.get(blank_texts, n))
        _ -> true
      end) ->
        {:reply, {:error, :invalid_blank_text}, state}

      true ->
        remaining_cards = player.hand -- cards

        players =
          Map.update!(state.players, player_id, fn player ->
            %{player | hand: remaining_cards}
          end)

        cards =
          Enum.map(cards, fn
            {:blank, n} ->
              {:custom, Map.get(blank_texts, n)}

            card ->
              card
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
  def handle_call({:discard, player_id, cards}, _, state) do
    player = Map.get(state.players, player_id)

    cond do
      player == nil ->
        {:reply, {:error, :no_player}, state}

      state.phase != :submitting ->
        {:reply, {:error, :wrong_phase}, state}

      length(Enum.uniq(cards)) != length(cards) ->
        {:reply, {:error, :duplicate_whites}, state}

      not Enum.all?(cards, &(&1 in player.hand)) ->
        {:reply, {:error, :not_in_hand}, state}

      cards == [] ->
        {:reply, {:error, :no_cards}, state}

      length(cards) > length(player.hand) ->
        {:reply, {:error, :too_many_discards}, state}

      Map.has_key?(state.submissions, player_id) ->
        {:reply, {:error, :already_submitted}, state}

      Map.has_key?(state.discarding, player_id) ->
        {:reply, {:error, :already_discarded}, state}

      true ->
        remaining_cards = player.hand -- cards

        discarding = Map.put_new(state.discarding, player_id, cards)

        players =
          Map.update!(state.players, player_id, fn player ->
            %{player | hand: remaining_cards, score: max(player.score - 1, 0)}
          end)

        state = %{
          state
          | discarding: discarding,
            players: players
        }

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
  def handle_call({:reset_game, player_id}, _, state) do
    is_host = state.host == player_id

    if is_host do
      state = do_reset(state)
      {:reply, :ok, state}
    else
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

        discard =
          state.discard ++
            (state.submissions
             |> Map.values()
             |> List.flatten()
             |> Enum.reject(&match?({:custom, _}, &1)))

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

  @impl true
  def handle_call({:leave, player_id}, _, state) do
    cond do
      not Map.has_key?(state.players, player_id) ->
        {:reply, {:error, :cannot_remove_not_existing}, state}

      true ->
        state =
          state
          |> remove_player(player_id)
          |> ensure_is_host()

        is_czar = state.czar == player_id

        state =
          cond do
            # we don't have enough people left
            state.phase in [:submitting, :judging] and
                Enum.count(state.players, fn {_id, player} -> player.connected end) < 3 ->
              PubSub.broadcast(:cah_pubsub, @topic, {:notice, :not_enough_players_left})
              do_reset(state)

            # we do have enough people, but the czar disconnected
            is_czar and state.phase in [:submitting, :judging] ->
              PubSub.broadcast(:cah_pubsub, @topic, {:notice, :czar_dropped})
              next_round(state)

            # we have enough people and the czar didn't drop, so see if we go on to the next phase
            state.phase == :submitting ->
              maybe_progress(state)

            true ->
              state
          end

        broadcast_state(state)

        {:reply, :ok, state}
    end
  end

  defp valid_blank_text?(nil), do: false

  defp valid_blank_text?(str) do
    trimmed = String.trim(str)
    trimmed != "" and String.length(trimmed) <= 120
  end

  defp next_round(state) do
    if Enum.count(state.players, fn {_id, player} -> player.connected end) > 2 do
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

      new_czar = find_czar(state)

      discard =
        state.discard ++
          (state.discarding
           |> Map.values()
           |> List.flatten())

      %{
        state
        | submissions: %{},
          reveal_order: [],
          czar: new_czar,
          black_card: black_card,
          black_deck: rest,
          phase: :submitting,
          discarding: %{},
          discard: discard
      }
    else
      PubSub.broadcast(:cah_pubsub, @topic, {:notice, :not_enough_players_left})
      do_reset(state)
    end
  end

  defp first_connected(state) do
    Enum.find(state.player_order, &state.players[&1].connected)
  end

  defp find_czar(state) do
    order = state.player_order

    i = Enum.find_index(order, &(&1 == state.czar)) || -1
    {before, after_czar} = Enum.split(order, i + 1)

    (after_czar ++ before)
    |> Enum.find(&state.players[&1].connected)
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    {player_id, monitors} = Map.pop(state.monitors, ref)
    state = %{state | monitors: monitors}

    state =
      case state.players[player_id] do
        %{pid: ^pid} ->
          timer = Process.send_after(self(), {:grace_expired, player_id}, 30_000)
          grace_timers = Map.put(state.grace_timers, player_id, timer)
          %{state | grace_timers: grace_timers}

        _ ->
          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:grace_expired, player_id}, state) do
    case Map.pop(state.grace_timers, player_id) do
      {nil, _} ->
        {:noreply, state}

      {_ref, timers} ->
        state = %{state | grace_timers: timers}

        if Map.has_key?(state.players, player_id) do
          state = put_in(state, [:players, player_id, :connected], false)

          state =
            if player_id == state.czar do
              if state.phase in [:submitting, :judging] do
                PubSub.broadcast(:cah_pubsub, @topic, {:notice, :czar_dropped})
                broadcast_state(state)
                next_round(state)
              else
                state
              end
            else
              maybe_progress(state)
            end

          state = ensure_is_host(state)

          timer = Process.send_after(self(), {:removal_expired, player_id}, 180_000)
          removal_timers = Map.put(state.removal_timers, player_id, timer)
          state = %{state | removal_timers: removal_timers}

          broadcast_state(state)
          {:noreply, state}
        else
          {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info({:removal_expired, player_id}, state) do
    case Map.pop(state.removal_timers, player_id) do
      {nil, _} ->
        {:noreply, state}

      {_ref, timers} ->
        state = %{state | removal_timers: timers}

        state = ensure_is_host(state)

        if Map.has_key?(state.players, player_id) do
          state = remove_player(state, player_id)
          broadcast_state(state)
          {:noreply, state}
        else
          {:noreply, state}
        end
    end
  end

  defp maybe_progress(state) do
    expected_size = Enum.count(state.players, fn {id, p} -> p.connected and id != state.czar end)
    submissions_num = map_size(state.submissions)
    discarding_num = map_size(state.discarding)

    cond do
      expected_size == submissions_num + discarding_num ->
        if submissions_num >= 2 do
          reveal_order = state.submissions |> Map.keys() |> Enum.shuffle()
          %{state | phase: :judging, reveal_order: reveal_order}
        else
          PubSub.broadcast(:cah_pubsub, @topic, {:notice, :too_many_players_discarding})
          next_round(state)
        end

      true ->
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
    state =
      case Map.pop(state.grace_timers, player_id) do
        {nil, _} ->
          state

        {timer, timers} ->
          Process.cancel_timer(timer)
          %{state | grace_timers: timers}
      end

    state =
      case Map.pop(state.removal_timers, player_id) do
        {nil, _} ->
          state

        {timer, timers} ->
          Process.cancel_timer(timer)
          %{state | removal_timers: timers}
      end

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
  end

  defp broadcast_state(state) do
    PubSub.broadcast(
      :cah_pubsub,
      @topic,
      {:game_state, public_state(state)}
    )
  end

  defp ensure_is_host(state) do
    case state.players[state.host] do
      %{connected: true} -> state
      _ -> %{state | host: first_connected(state)}
    end
  end

  defp do_reset(state) do
    connected_players = Enum.filter(state.player_order, &state.players[&1].connected)
    players = Map.take(state.players, connected_players)

    players =
      Map.new(players, fn {id, player} ->
        {id, %{player | score: 0, hand: []}}
      end)

    Enum.each(state.grace_timers, fn {_id, timer} -> Process.cancel_timer(timer) end)
    Enum.each(state.removal_timers, fn {_id, timer} -> Process.cancel_timer(timer) end)

    state = %{
      state
      | submissions: %{},
        players: players,
        player_order: connected_players,
        grace_timers: %{},
        removal_timers: %{},
        discard: [],
        discarding: %{},
        reveal_order: [],
        czar: nil,
        black_card: nil,
        black_deck: Cah.Cards.deal_black(),
        white_deck: Cah.Cards.deal_white(),
        phase: :lobby
    }

    state = ensure_is_host(state)

    Enum.each(state.players, fn {id, _player} ->
      send_hand(state, id)
    end)

    broadcast_state(state)
    state
  end

  defp public_state(state) do
    players =
      Enum.map(state.player_order, fn id ->
        player = state.players[id]

        %{
          id: id,
          name: player.name,
          connected: player.connected,
          submitted: Map.has_key?(state.submissions, id),
          score: player.score,
          discarded: Map.has_key?(state.discarding, id),
          host: state.host
        }
      end)

    lobby_phase = state.phase
    black_card = state.black_card
    czar = state.czar
    target_score = state.target_score
    host = state.host

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
      submissions: submissions,
      target_score: target_score,
      host: host
    }
  end
end
