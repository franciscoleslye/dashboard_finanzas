defmodule DashboardFinanzas.Finanzas do
  import Ecto.Query, warn: false
  alias DashboardFinanzas.Repo
  alias DashboardFinanzas.Finanzas.Indicador
  alias DashboardFinanzas.CmfClient

  @doc """
  Crea un registro de indicador. Usado por el proceso de sincronización.
  """
  def create_indicador(attrs \\ %{}) do
    %Indicador{}
    |> Indicador.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:nombre, :fecha]
    )
  end

  @doc """
  Obtiene los últimos valores de todos los indicadores desde la DB.
  Útil como "fallback" si la API de la CMF está caída.
  """
  def obtener_indicadores_recientes do
    nombres = ["UF", "Dólar", "Euro", "UTM", "IPC"]

    # Esta query obtiene el último registro para cada nombre en la lista
    query =
      from i in Indicador,
        where: i.nombre in ^nombres,
        distinct: i.nombre,
        order_by: [desc: i.fecha, desc: i.nombre]

    Repo.all(query)
  end

  @doc """
  Sincroniza todos los indicadores de una vez.
  Llama a la API y guarda cada resultado en la base de datos.
  """
  def sincronizar_todo do
    case CmfClient.obtener_indicadores_completos() do
      {:ok, data} ->
        # Iteramos sobre el mapa de resultados para insertarlos uno a uno
        resultados =
          Enum.map(data, fn {clave, info} ->
            nombre_legible = clave_a_nombre(clave)

            create_indicador(%{
              nombre: nombre_legible,
              valor: info.valor,
              fecha: info.fecha
            })
          end)

        {:ok, resultados}
    end
  end

  # Helper privado para mapear el átomo interno al nombre de la DB
  defp clave_a_nombre(:uf), do: "UF"
  defp clave_a_nombre(:dolar), do: "Dólar"
  defp clave_a_nombre(:euro), do: "Euro"
  defp clave_a_nombre(:utm), do: "UTM"
  defp clave_a_nombre(:ipc), do: "IPC"
  defp clave_a_nombre(otro), do: Atom.to_string(otro)
end
