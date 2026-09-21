defmodule Cah.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CahWeb.Telemetry,
      Cah.Repo,
      {DNSCluster, query: Application.get_env(:cah, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: :cah_pubsub},
      Cah.CahServer,
      # Start a worker by calling: Cah.Worker.start_link(arg)
      # {Cah.Worker, arg},
      # Start to serve requests, typically the last entry
      CahWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Cah.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CahWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
