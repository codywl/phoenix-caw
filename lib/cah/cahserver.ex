defmodule Cah.CahServer do
  use GenServer
  alias Phoenix.PubSub

  @topic "cah:game"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def join(pid) do
    GenServer.call(__MODULE__, {:join, pid})
  end

  def leave(pid) do
    GenServer.call(__MODULE__, {:leave, pid})
  end

  def players do
    GenServer.call(__MODULE__, :players)
  end

  @impl true
  def init(_) do
    {:ok, %{host: nil, players: []}}
  end

  @impl true
  def handle_call({:join, pid}, _, state) do
    if pid not in state.players do
      Process.monitor(pid)
      state = %{state | players: state.players ++ [pid]}

      {role, new_state} =
        if state.host == nil do
          {:host, %{state | host: pid}}
        else
          {:player, state}
        end

      broadcast_players(state)
      {:reply, {:ok, role}, new_state}
    else
      new_state = state
      role = if state.host == pid, do: :host, else: :player
      broadcast_players(state)
      {:reply, {:ok, role}, new_state}
    end
  end

  @impl true
  def handle_call(:players, _, state) do
    {:reply, state.players, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, remove_player(state, pid)}
  end

  @impl true
  def handle_cast({:leave, pid}, state) do
    {:noreply, remove_player(state, pid)}
  end

  defp remove_player(state, pid) do
    if Enum.any?(state.players, fn x -> x == pid end) do
      %{state | players: Enum.filter(state.players, fn x -> x != pid end)}
    else
      state
    end
    |> tap(&broadcast_players/1)
  end

  defp broadcast_players(state) do
    PubSub.broadcast(:cah_pubsub, @topic, {:players, state.players})
  end
end
