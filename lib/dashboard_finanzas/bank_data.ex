defmodule DashboardFinanzas.BankData do
  require Logger

  @api_key "a48b40e69d075d6b88b7343cd0dc057317e2ff5b"
  @base_url "https://api.cmfchile.cl/api-sbifv3/recursos_api"

  def obtener_balance_resumen(year, month, institution \\ "001") do
    url = "#{@base_url}/balances/#{year}/#{month}/instituciones/#{institution}"
    query_params = [apikey: @api_key]

    headers = %{
      "user-agent" => "Mozilla/5.0",
      "accept" => "application/xml"
    }

    case Req.get(url, params: query_params, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        parse_balance_summary(body, year, month)

      {:ok, %{status: status}} ->
        {:error, "Status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def obtener_estado_resultados(year, month, institution \\ "001") do
    url = "#{@base_url}/resultados/#{year}/#{month}/instituciones/#{institution}"
    query_params = [apikey: @api_key]

    headers = %{
      "user-agent" => "Mozilla/5.0",
      "accept" => "application/xml"
    }

    case Req.get(url, params: query_params, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        parse_estado_resultados(body, year, month)

      {:ok, %{status: status}} ->
        {:error, "Status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def obtener_bancos(year, month) do
    url = "#{@base_url}/balances/#{year}/#{month}/instituciones"
    query_params = [apikey: @api_key]

    headers = %{
      "user-agent" => "Mozilla/5.0",
      "accept" => "application/xml"
    }

    case Req.get(url, params: query_params, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        parse_instituciones(body)

      {:ok, %{status: status}} ->
        {:error, "Status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_balance_summary(body, year, month) do
    total_activos_pattern =
      ~r/DescripcionCuenta>TOTAL ACTIVOS<\/DescripcionCuenta>.*?<MonedaTotal>([^<]+)<\/MonedaTotal>/s

    total_pasivos_pattern =
      ~r/DescripcionCuenta>TOTAL PASIVOS<\/DescripcionCuenta>.*?<MonedaTotal>([^<]+)<\/MonedaTotal>/s

    with {:ok, activos} <- extract_value(body, total_activos_pattern),
         {:ok, pasivos} <- extract_value(body, total_pasivos_pattern) do
      {:ok,
       %{
         activos: parse_decimal(activos),
         pasivos: parse_decimal(pasivos),
         year: year,
         month: month
       }}
    else
      :error -> {:error, "No balance summary found"}
    end
  rescue
    e ->
      Logger.error("Parse error: #{inspect(e)}")
      {:error, "Error parsing balance data"}
  end

  defp parse_estado_resultados(body, year, month) do
    ingresos_pattern =
      ~r/DescripcionCuenta>TOTAL INGRESOS OPERACIONALES<\/DescripcionCuenta>.*?<MonedaTotal>([^<]+)<\/MonedaTotal>/s

    gastos_pattern =
      ~r/DescripcionCuenta>TOTAL GASTOS OPERACIONALES<\/DescripcionCuenta>.*?<MonedaTotal>([^<]+)<\/MonedaTotal>/s

    with {:ok, ingresos_raw} <- extract_value(body, ingresos_pattern),
         {:ok, gastos_raw} <- extract_value(body, gastos_pattern) do
      ingresos = parse_decimal(ingresos_raw)
      gastos = parse_decimal(gastos_raw)
      resultado = Decimal.add(ingresos, gastos)

      {:ok,
       %{
         ingresos: ingresos,
         gastos: gastos,
         resultado: resultado,
         year: year,
         month: month
       }}
    else
      :error -> {:error, "No result summary found"}
    end
  rescue
    e ->
      Logger.error("Parse estado resultados error: #{inspect(e)}")
      {:error, "Error parsing estado de resultados"}
  end

  defp parse_instituciones(body) do
    pattern =
      ~r/CodigoInstitucion>(\d+)<\/CodigoInstitucion><NombreInstitucion>([^<]+)<\/NombreInstitucion>/

    banks =
      Regex.scan(pattern, body, capture: :all_but_first)
      |> Enum.map(fn [code, name] -> %{code: code, name: name} end)
      |> Enum.reject(fn %{name: name} -> name == "" end)

    {:ok, banks}
  rescue
    _ -> {:error, "Error parsing institutions"}
  end

  defp extract_value(body, pattern) do
    case Regex.run(pattern, body, capture: :all_but_first) do
      [value] -> {:ok, value}
      _ -> :error
    end
  end

  defp parse_decimal(""), do: Decimal.new(0)

  defp parse_decimal(valor_str) do
    valor_str
    |> String.trim()
    |> String.replace(".", "")
    |> String.replace(",", ".")
    |> Decimal.new()
  end

  def periodo_disponible_actual(lookback_months \\ 12) do
    today = Date.utc_today()

    1..lookback_months
    |> Enum.map(&Date.add(today, -30 * &1))
    |> Enum.map(fn date -> {date.year, date.month} end)
    |> Enum.uniq()
    |> Enum.reduce_while({:error, :no_reporting_period_found}, fn {year, month}, _acc ->
      case obtener_bancos(year, month) do
        {:ok, banks} when banks != [] -> {:halt, {:ok, {year, month}}}
        _ -> {:cont, {:error, :no_reporting_period_found}}
      end
    end)
  end

  def obtener_todos_bancos_con_datos(year, month) do
    case Cachex.get(:bank_cache, "banks_#{year}_#{month}") do
      {:ok, nil} ->
        fetch_all_banks_data(year, month)

      {:ok, data} ->
        {:ok, data}

      {:error, _} ->
        fetch_all_banks_data(year, month)
    end
  end

  defp fetch_all_banks_data(year, month) do
    with {:ok, banks} <- obtener_bancos(year, month) do
      banks_data =
        Enum.map(banks, fn bank ->
          balance =
            case obtener_balance_resumen(year, month, bank.code) do
              {:ok, b} -> b
              {:error, _} -> nil
            end

          resultado =
            case obtener_estado_resultados(year, month, bank.code) do
              {:ok, r} -> r
              {:error, _} -> nil
            end

          Process.sleep(200)

          %{
            code: bank.code,
            name: bank.name,
            balance: balance,
            resultados: resultado
          }
        end)

      banks_data = Enum.filter(banks_data, fn b -> b.balance != nil or b.resultados != nil end)
      Cachex.put(:bank_cache, "banks_#{year}_#{month}", banks_data, ttl: :timer.hours(6))

      {:ok, banks_data}
    end
  end

  def limpiar_cache_bancos() do
    Cachex.clear(:bank_cache)
  end
end
