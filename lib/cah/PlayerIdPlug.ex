defmodule CahWeb.Plugs.PlayerId do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, "player_id") do
      conn
    else
      put_session(conn, "player_id", Ecto.UUID.generate())
    end
  end
end
