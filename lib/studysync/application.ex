defmodule Studysync.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    node_js_children =
      if Application.get_env(:live_svelte, :ssr_module, nil) == LiveSvelte.SSR.NodeJS do
        [{NodeJS.Supervisor, [path: LiveSvelte.SSR.NodeJS.server_path(), pool_size: 4]}]
      else
        []
      end

    children =
      node_js_children ++
        [
          StudysyncWeb.Telemetry,
          Studysync.Repo,
          {DNSCluster, query: Application.get_env(:studysync, :dns_cluster_query) || :ignore},
          {Oban,
           AshOban.config(
             Application.fetch_env!(:studysync, :ash_domains),
             Application.fetch_env!(:studysync, Oban)
           )},
          {Phoenix.PubSub, name: Studysync.PubSub},
          Studysync.Presence,
          Studysync.Chat.Buffer,
          # Start a worker by calling: Studysync.Worker.start_link(arg)
          # {Studysync.Worker, arg},
          # Start to serve requests, typically the last entry
          StudysyncWeb.Endpoint,
          {AshAuthentication.Supervisor, [otp_app: :studysync]}
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Studysync.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Slice 15.3 — log slow LV / annotation / PubSub events in dev only.
    # The handler is detached automatically when the application stops.
    if Application.get_env(:studysync, :dev_telemetry_logger?, false) do
      Studysync.Telemetry.DevLogger.attach()
    end

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    StudysyncWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
