defmodule DashboardFinanzas.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DashboardFinanzasWeb.Telemetry,
      DashboardFinanzas.Repo,
      Supervisor.child_spec({Cachex, [name: :cmf_cache]}, id: :cmf_cache),
      Supervisor.child_spec({Cachex, [name: :bank_cache]}, id: :bank_cache),
      Supervisor.child_spec({Cachex, [name: :congress_cache]}, id: :congress_cache),
      Supervisor.child_spec({Cachex, [name: :diputados_cache]}, id: :diputados_cache),
      Supervisor.child_spec({Cachex, [name: :senadores_cache]}, id: :senadores_cache),
      {DNSCluster,
       query: Application.get_env(:dashboard_finanzas, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DashboardFinanzas.PubSub},
      {Finch, name: DashboardFinanzas.Finch},
      DashboardFinanzas.BankDataServer,
      DashboardFinanzas.CmfIndicatorsScheduler,
      {Oban, oban_config()},
      DashboardFinanzasWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: DashboardFinanzas.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp oban_config do
    Application.get_env(:dashboard_finanzas, Oban) ++ [repo: DashboardFinanzas.Repo]
  end

  @impl true
  def config_change(changed, _new, removed) do
    DashboardFinanzasWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
