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

  def players do
    GenServer.call(__MODULE__, :players)
  end

  @impl true
  def init(_) do
    {:ok, %{host: nil, players: %{}, monitors: %{}}}
  end

  @impl true
  def handle_call({:join, player_id, pid, name}, _, state) do
    players =
      case Map.fetch(state.players, player_id) do
        {:ok, player} ->
          Map.put(state.players, player_id, %{player | pid: pid, connected: true})

        :error ->
          Map.put(state.players, player_id, %{name: name, pid: pid, connected: true})
      end

    host = state.host || player_id
    role = if host == player_id, do: :host, else: :player
    ref = Process.monitor(pid)
    monitors = Map.put(state.monitors, ref, player_id)
    state = %{state | players: players, monitors: monitors, host: host}

    broadcast_players(state)
    {:reply, {:ok, role}, state}
  end

  @impl true
  def handle_call(:players, _, state) do
    {:reply, state.players, state}
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

    broadcast_players(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:leave, player_id}, state) do
    {:noreply, remove_player(state, player_id)}
  end

  defp remove_player(state, player_id) do
    %{state | players: Map.delete(state.players, player_id)}
    |> tap(&broadcast_players/1)
  end

  defp broadcast_players(state) do
    PubSub.broadcast(:cah_pubsub, @topic, {:players, state.players})
  end
end
