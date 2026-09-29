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
       discard: []
     }}
  end

  @impl true
  def handle_call({:start_game, player_id}, _, state) do
    is_host = state.host == player_id
    has_enough_players = map_size(state.players) > 2

    cond do
      is_host and has_enough_players ->
        state =
          Enum.reduce(Map.keys(state.players), state, fn id, state -> draw(state, id, 10) end)

        state = %{state | phase: :playing}
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
        hand: []
      })

    state = %{state | players: players}
    state = if is_new?, do: draw(state, player_id, 10), else: state

    {role, state} = attach(state, player_id, pid)
    {:reply, {:ok, role}, state}
  end

  @impl true
  def handle_call(:game_state, _, state) do
    {:reply, public_state(state), state}
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

  defp send_hand(state, player_id) do
    case Map.get(state.players, player_id) do
      %{pid: pid, hand: hand} when is_pid(pid) -> send(pid, {:hand, hand})
      _ -> :ok
    end
  end

  defp draw(state, player_id, n) do
    {drawn_cards, rest} = Enum.split(state.white_deck, n)

    players =
      Map.update!(state.players, player_id, fn player ->
        %{player | hand: player.hand ++ drawn_cards}
      end)

    %{state | players: players, white_deck: rest}
    send_hand(state, player_id)
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
    %{state | players: Map.delete(state.players, player_id)}
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
      Enum.map(state.players, fn {id, player} ->
        %{id: id, name: player.name, connected: player.connected}
      end)

    lobby_phase = state.phase
    %{players: players, phase: lobby_phase}
  end
end
