defmodule DashboardFinanzas.Finanzas.Sync do
  require Logger
  alias DashboardFinanzas.Finanzas

  @doc """
  Ejecuta la sincronización masiva de todos los indicadores financieros.
  Limpia los resultados y genera logs de éxito o error.
  """
  def ejecutar_sincronizacion do
    Logger.info("[Sync] Iniciando sincronización de indicadores desde la CMF...")

    case Finanzas.sincronizar_todo() do
      {:ok, resultados} ->
        # Contamos cuántos se insertaron vs cuántos fueron ignorados (por duplicado)
        total = Enum.count(resultados)
        exitosos = Enum.count(resultados, fn {status, _} -> status == :ok end)
        duplicados = total - exitosos

        Logger.info("[Sync] Sincronización finalizada con éxito.")

        Logger.info(
          "[Sync] Procesados: #{total} | Nuevos: #{exitosos} | Ya existentes: #{duplicados}"
        )

        {:ok, %{total: total, nuevos: exitosos, ignorados: duplicados}}
    end
  end
end
