defmodule DashboardFinanzas.CmfIndicatorsWorker do
  use Oban.Worker, queue: :cmf_indicators

  alias DashboardFinanzas.CmfClient

  @impl true
  def perform(%Oban.Job{args: %{"task" => "fetch_indicators"}}) do
    fetch_and_cache_indicators()
    :ok
  end

  @impl true
  def perform(%Oban.Job{args: %{"task" => "fetch_uf_history"}}) do
    fetch_and_cache_uf_history()
    :ok
  end

  @impl true
  def perform(%Oban.Job{args: %{"task" => "fetch_all"}}) do
    fetch_and_cache_indicators()
    fetch_and_cache_uf_history()
    :ok
  end

  defp fetch_and_cache_indicators do
    {:ok, data} = CmfClient.obtener_indicadores_completos()
    Cachex.put(:cmf_cache, "all_indicators", data, ttl: :timer.hours(6))
    Logger.info("[CmfIndicatorsWorker] Fetched and cached indicators: #{inspect(data)}")
    {:ok, "Fetched CMF indicators"}
  end

  defp fetch_and_cache_uf_history do
    {:ok, history} = CmfClient.obtener_historial_uf(1)
    Cachex.put(:cmf_cache, "uf_history_1", history, ttl: :timer.hours(24))
    Logger.info("[CmfIndicatorsWorker] Fetched and cached UF history: #{length(history)} entries")
    {:ok, "Fetched UF history"}
  end

  require Logger
end
