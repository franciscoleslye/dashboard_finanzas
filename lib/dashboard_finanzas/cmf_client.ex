defmodule DashboardFinanzas.CmfClient do
  require Logger

  @api_key "a48b40e69d075d6b88b7343cd0dc057317e2ff5b"
  @base_url "https://api.cmfchile.cl/api-sbifv3/recursos_api"

  def obtener_indicadores_completos() do
    Logger.info("[CmfClient] ===== START obtener_indicadores_completos =====")

    cache_check = Cachex.get(:cmf_cache, "all_indicators")
    Logger.info("[CmfClient] Manual cache check: #{inspect(cache_check)}")

    result =
      case cache_check do
        {:ok, nil} ->
          Logger.info("[CmfClient] Cache MISS, fetching...")
          fetch_and_cache_indicators()

        {:ok, data} ->
          Logger.info("[CmfClient] Cache HIT with data!")
          {:ok, data}

        {:error, reason} ->
          Logger.warning("[CmfClient] Cache error: #{inspect(reason)}")
          fetch_and_cache_indicators()
      end

    Logger.info("[CmfClient] ===== END result: #{inspect(result)} =====")
    result
  end

  def obtener_uf_actual(), do: fetch_indicator("/uf", "UF")
  def obtener_dolar_actual(), do: fetch_dolar_year()
  def obtener_euro_actual(), do: fetch_euro_year()
  def obtener_utm_actual(), do: fetch_indicator("/utm", "UTM")
  def obtener_ipc_actual(), do: fetch_indicator("/ipc", "IPC")

  defp fetch_and_cache_indicators() do
    Logger.info("[CmfClient] ===== fetch_and_cache_indicators START =====")

    uf_result = obtener_uf_actual()
    Logger.info("[CmfClient] UF result: #{inspect(uf_result)}")

    dolar_result = obtener_dolar_actual()
    Logger.info("[CmfClient] Dolar result: #{inspect(dolar_result)}")

    euro_result = obtener_euro_actual()
    Logger.info("[CmfClient] Euro result: #{inspect(euro_result)}")

    utm_result = obtener_utm_actual()
    Logger.info("[CmfClient] UTM result: #{inspect(utm_result)}")

    ipc_result = obtener_ipc_actual()
    Logger.info("[CmfClient] IPC result: #{inspect(ipc_result)}")

    data = %{
      uf: safely_extract_result(uf_result),
      dolar: safely_extract_result(dolar_result),
      euro: safely_extract_result(euro_result),
      utm: safely_extract_result(utm_result),
      ipc: safely_extract_result(ipc_result)
    }

    Logger.info("[CmfClient] Final data: #{inspect(data)}")

    Cachex.put(:cmf_cache, "all_indicators", data, ttl: :timer.hours(6))
    Logger.info("[CmfClient] Cached data!")
    {:ok, data}
  end

  defp safely_extract_result({:ok, data}), do: data

  defp safely_extract_result({:error, reason}) do
    if is_binary(reason) and String.contains?(reason, "Status"),
      do: %{valor: nil, fecha: nil},
      else: %{valor: nil, fecha: nil}
  end

  defp fetch_indicator(path, xml_tag) do
    url = "#{@base_url}#{path}"
    query_params = [apikey: @api_key]

    headers = %{
      "user-agent" => "Mozilla/5.0",
      "accept" => "application/xml"
    }

    case Req.get(url, params: query_params, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        parse_xml_response(body, xml_tag)

      {:ok, %{status: status}} ->
        {:error, "Status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_dolar_year do
    year = Date.utc_today().year
    url = "#{@base_url}/dolar/#{year}"
    query_params = [apikey: @api_key]

    headers = %{
      "user-agent" => "Mozilla/5.0",
      "accept" => "application/xml"
    }

    case Req.get(url, params: query_params, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        parse_dolar_year(body)

      {:ok, %{status: status}} ->
        {:error, "Status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_euro_year do
    year = Date.utc_today().year
    url = "#{@base_url}/euro/#{year}"
    query_params = [apikey: @api_key]

    headers = %{
      "user-agent" => "Mozilla/5.0",
      "accept" => "application/xml"
    }

    case Req.get(url, params: query_params, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        parse_euro_year(body)

      {:ok, %{status: status}} ->
        {:error, "Status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_dolar_year(body) do
    pattern = ~r/<Dolar><Fecha>([^<]+)<\/Fecha><Valor>([^<]+)<\/Valor><\/Dolar>/

    dolares =
      Regex.scan(pattern, body, capture: :all_but_first)
      |> Enum.map(fn [fecha, valor] ->
        %{fecha: parse_xml_date(fecha), valor: parse_decimal(valor)}
      end)

    case List.last(dolares) do
      nil -> {:error, "No se pudieron obtener datos del dólar"}
      latest -> {:ok, latest}
    end
  end

  defp parse_euro_year(body) do
    pattern = ~r/<Euro><Fecha>([^<]+)<\/Fecha><Valor>([^<]+)<\/Valor><\/Euro>/

    euros =
      Regex.scan(pattern, body, capture: :all_but_first)
      |> Enum.map(fn [fecha, valor] ->
        %{fecha: parse_xml_date(fecha), valor: parse_decimal(valor)}
      end)

    case List.last(euros) do
      nil -> {:error, "No se pudieron obtener datos del euro"}
      latest -> {:ok, latest}
    end
  end

  defp fetch_indicator_with_date_fallback(path, xml_tag) do
    today = Date.utc_today()
    dates = for offset <- -1..-30//-1, do: Date.add(today, offset)
    today_result = fetch_indicator_with_date(path, xml_tag, format_date(today))

    if is_tuple(today_result) && elem(today_result, 0) == :ok do
      today_result
    else
      find_in_dates(path, xml_tag, dates)
    end
  end

  defp find_in_dates(_path, _xml_tag, []), do: {:error, "No data available"}

  defp find_in_dates(path, xml_tag, [date | rest]) do
    case fetch_indicator_with_date(path, xml_tag, format_date(date)) do
      {:ok, _} = result -> result
      _ -> find_in_dates(path, xml_tag, rest)
    end
  end

  defp format_date(date) do
    "#{String.pad_leading(Integer.to_string(date.day), 2, "0")}-#{String.pad_leading(Integer.to_string(date.month), 2, "0")}-#{date.year}"
  end

  defp fetch_indicator_with_date(path, xml_tag, fecha) do
    url = "#{@base_url}#{path}/#{fecha}"
    query_params = [apikey: @api_key]

    headers = %{
      "user-agent" => "Mozilla/5.0",
      "accept" => "application/xml"
    }

    case Req.get(url, params: query_params, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        parse_xml_response(body, xml_tag)

      {:ok, %{status: status}} ->
        {:error, "Status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_xml_response(body, xml_tag) do
    fecha_pattern = ~r/<#{xml_tag}>.*?<Fecha>([^<]+)<\/Fecha>/
    valor_pattern = ~r/<#{xml_tag}>.*?<Valor>([^<]+)<\/Valor>/

    with {:ok, fecha} <- extract_match(body, fecha_pattern),
         {:ok, valor} <- extract_match(body, valor_pattern) do
      {:ok, %{valor: parse_decimal(valor), fecha: parse_xml_date(fecha)}}
    else
      _ -> {:error, "No se pudo parsear #{xml_tag}"}
    end
  end

  defp extract_match(body, pattern) do
    case Regex.run(pattern, body, capture: :all_but_first) do
      [match] -> {:ok, match}
      _ -> :error
    end
  end

  defp parse_xml_date(""), do: Date.utc_today()

  defp parse_xml_date(fecha_str) do
    case Date.from_iso8601(fecha_str) do
      {:ok, date} -> date
      _ -> Date.utc_today()
    end
  end

  defp parse_decimal(valor_str) do
    valor_str
    |> String.trim()
    |> String.replace(".", "")
    |> String.replace(",", ".")
    |> Decimal.new()
  end

  def obtener_historial_uf(anios \\ 1) do
    anio_actual = Date.utc_today().year
    anio_inicio = anio_actual - anios

    case Cachex.get(:cmf_cache, "uf_history_#{anios}") do
      {:ok, nil} ->
        fetch_uf_historical(anio_inicio, anio_actual)

      {:ok, data} ->
        {:ok, data}

      {:error, reason} ->
        Logger.warning("[CmfClient] Cache error fetching UF history: #{inspect(reason)}")
        fetch_uf_historical(anio_inicio, anio_actual)
    end
  end

  defp fetch_uf_historical(anio_inicio, anio_fin) do
    url = "#{@base_url}/uf/periodo/#{anio_inicio}/#{anio_fin}"
    query_params = [apikey: @api_key, formato: "JSON"]

    headers = %{
      "user-agent" => "Mozilla/5.0",
      "accept" => "application/json"
    }

    case Req.get(url, params: query_params, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        parsed = parse_uf_history(body)

        Cachex.put(:cmf_cache, "uf_history_#{anio_fin - anio_inicio}", parsed,
          ttl: :timer.hours(24)
        )

        {:ok, parsed}

      {:ok, %{status: status}} ->
        {:error, "Status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_uf_history(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, data} ->
        parse_uf_json(data)

      _ ->
        []
    end
  end

  defp parse_uf_json(data) when is_map(data) do
    series = Map.get(data, "UFs") || Map.get(data, "UF") || []

    series
    |> Enum.map(fn item ->
      valor =
        item["Valor"]
        |> String.replace(".", "")
        |> String.replace(",", ".")

      %{
        fecha: item["Fecha"],
        valor: Decimal.new(valor)
      }
    end)
    |> Enum.filter(fn %{fecha: f} -> f != nil and f != "" end)
  end

  defp parse_uf_json(_), do: []
end
