defmodule Cah.Repo do
  use Ecto.Repo,
    otp_app: :cah,
    adapter: Ecto.Adapters.Postgres
end
