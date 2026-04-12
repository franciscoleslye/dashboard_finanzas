defmodule DashboardFinanzas.ClientDiputados do
  import SweetXml
  require Logger

  @base_url "https://opendata.camara.cl/camaradiputados/WServices"
  @comun_base_url "https://opendata.camara.cl/camaradiputados/WServices/WSComun.asmx"
  @default_headers %{
    "user-agent" => "Mozilla/5.0",
    "accept" => "application/xml"
  }

  def get_diputados_vigentes() do
    cache_key = "diputados_vigentes"

    with {:ok, cached} <- Cachex.get(:diputados_cache, cache_key) do
      case cached do
        nil ->
          fetch_and_cache_diputados(cache_key)

        deputies ->
          {:ok, deputies}
      end
    else
      {:error, reason} ->
        Logger.warning("[ClientDiputados] Cache error: #{inspect(reason)}")
        fetch_and_cache_diputados(cache_key)
    end
  end

  defp fetch_and_cache_diputados(cache_key) do
    with {:ok, period_id, period_range} <- get_current_period(),
         {:ok, body} <-
           get_xml("#{@base_url}/WSDiputado.asmx/retornarDiputadosXPeriodo",
             params: [prmPeriodoId: period_id]
           ) do
      deputies =
        body
        |> xpath(~x"//*[local-name()='DiputadoPeriodo']"l,
          id: ~x"./*[local-name()='Diputado']/*[local-name()='Id']/text()"s,
          nombre: ~x"./*[local-name()='Diputado']/*[local-name()='Nombre']/text()"s,
          nombre2: ~x"./*[local-name()='Diputado']/*[local-name()='Nombre2']/text()"s,
          apellido_paterno:
            ~x"./*[local-name()='Diputado']/*[local-name()='ApellidoPaterno']/text()"s,
          apellido_materno:
            ~x"./*[local-name()='Diputado']/*[local-name()='ApellidoMaterno']/text()"s,
          fecha_inicio: ~x"./*[local-name()='FechaInicio']/text()"s,
          fecha_termino: ~x"./*[local-name()='FechaTermino']/text()"s,
          partido:
            ~x"./*[local-name()='Diputado']/*[local-name()='Militancias']/*[local-name()='Militancia'][last()]/*[local-name()='Partido']/*[local-name()='Alias']/text()"s,
          partido_nombre:
            ~x"./*[local-name()='Diputado']/*[local-name()='Militancias']/*[local-name()='Militancia'][last()]/*[local-name()='Partido']/*[local-name()='Nombre']/text()"s,
          distrito_numero: ~x"./*[local-name()='Distrito']/*[local-name()='Numero']/text()"s,
          cargo: ~x"./*[local-name()='Cargo']/text()"s
        )
        |> Enum.filter(&active_in_period?(&1, period_range))
        |> Enum.map(&parse_deputy/1)
        |> Enum.sort_by(& &1.nombre)

      Cachex.put(:diputados_cache, cache_key, deputies, ttl: :timer.hours(12))
      {:ok, deputies}
    end
  end

  def get_asistencia(year \\ nil) do
    year = year || Date.utc_today().year
    cache_key = "asistencia_#{year}"

    with {:ok, cached} <- Cachex.get(:diputados_cache, cache_key) do
      case cached do
        nil ->
          fetch_and_cache_asistencia(year, cache_key)

        data ->
          {:ok, data}
      end
    else
      {:error, _} ->
        fetch_and_cache_asistencia(year, cache_key)
    end
  end

  defp fetch_and_cache_asistencia(year, cache_key) do
    with {:ok, body} <-
           get_xml("#{@base_url}/WSSala.asmx/retornarSesionesXAnno", params: [prmAnno: year]) do
      sesiones =
        body
        |> xpath(~x"//*[local-name()='Sesion']"l,
          id: ~x"./*[local-name()='Id']/text()"s,
          estado: ~x"./*[local-name()='Estado']/text()"s
        )
        |> Enum.filter(fn s -> s.estado == "Celebrada" end)
        |> Enum.map(& &1.id)
        |> Enum.take(50)

      attendance =
        Enum.reduce(sesiones, %{}, fn sesion_id, acc ->
          case fetch_session_attendance(sesion_id) do
            {:ok, attendees} ->
              Enum.reduce(attendees, acc, fn %{id: dip_id, tipo: tipo}, inner_acc ->
                current = Map.get(inner_acc, dip_id, %{asistencias: 0, sesiones: 0})
                asistio = tipo == "1"

                Map.put(inner_acc, dip_id, %{
                  asistencias: current.asistencias + if(asistio, do: 1, else: 0),
                  sesiones: current.sesiones + 1
                })
              end)

            _ ->
              acc
          end
        end)

      data =
        Enum.map(attendance, fn {id, data} ->
          pct = if(data.sesiones > 0, do: round(data.asistencias / data.sesiones * 100), else: 0)

          {id,
           %{
             asistencia: data.asistencias,
             inasistencias: data.sesiones - data.asistencias,
             porcentaje: pct
           }}
        end)
        |> Map.new()

      Cachex.put(:diputados_cache, cache_key, data, ttl: :timer.hours(6))
      {:ok, data}
    end
  end

  defp fetch_session_attendance(sesion_id) do
    with {:ok, body} <-
           get_xml("#{@base_url}/WSSala.asmx/retornarSesionAsistencia",
             params: [prmSesionId: sesion_id]
           ) do
      attendees =
        body
        |> xpath(~x"//*[local-name()='Asistencia']"l,
          id: ~x"./*[local-name()='Diputado']/*[local-name()='Id']/text()"s,
          tipo: ~x"./*[local-name()='TipoAsistencia']/@Valor"s
        )
        |> Enum.map(fn a -> %{id: parse_int(a.id), tipo: a.tipo} end)

      {:ok, attendees}
    else
      _ -> {:ok, []}
    end
  end

  def get_partidos() do
    cache_key = "partidos"

    with {:ok, cached} <- Cachex.get(:diputados_cache, cache_key) do
      case cached do
        nil ->
          fetch_and_cache_partidos(cache_key)

        data ->
          {:ok, data}
      end
    else
      {:error, _} ->
        fetch_and_cache_partidos(cache_key)
    end
  end

  defp fetch_and_cache_partidos(cache_key) do
    with {:ok, body} <- get_xml("#{@comun_base_url}/retornarPartidos") do
      partidos =
        body
        |> xpath(~x"//*[local-name()='Partido']"l,
          id: ~x"./*[local-name()='Id']/text()"s,
          nombre: ~x"./*[local-name()='Nombre']/text()"s,
          alias: ~x"./*[local-name()='Alias']/text()"s
        )
        |> Enum.map(fn p -> %{id: p.id, nombre: p.nombre, alias: p.alias} end)

      Cachex.put(:diputados_cache, cache_key, partidos, ttl: :timer.hours(24))
      {:ok, partidos}
    end
  end

  def get_sesiones(year \\ nil) do
    year = year || Date.utc_today().year
    cache_key = "sesiones_#{year}"

    with {:ok, cached} <- Cachex.get(:diputados_cache, cache_key) do
      case cached do
        nil ->
          fetch_and_cache_sesiones(year, cache_key)

        data ->
          {:ok, data}
      end
    else
      {:error, _} ->
        fetch_and_cache_sesiones(year, cache_key)
    end
  end

  defp fetch_and_cache_sesiones(year, cache_key) do
    with {:ok, body} <-
           get_xml("#{@base_url}/WSSala.asmx/retornarSesionesXAnno", params: [prmAnno: year]) do
      sesiones =
        body
        |> xpath(~x"//*[local-name()='Sesion']"l,
          id: ~x"./*[local-name()='Id']/text()"s,
          numero: ~x"./*[local-name()='Numero']/text()"s,
          fecha: ~x"./*[local-name()='FechaInicio']/text()"s,
          tipo: ~x"./*[local-name()='Tipo']/text()"s,
          estado: ~x"./*[local-name()='Estado']/text()"s
        )
        |> Enum.map(fn s ->
          %{
            id: s.id,
            numero: s.numero,
            fecha: parse_date(s.fecha),
            tipo: s.tipo,
            estado: s.estado
          }
        end)
        |> Enum.sort_by(& &1.fecha, {:desc, Date})
        |> Enum.take(20)

      Cachex.put(:diputados_cache, cache_key, sesiones, ttl: :timer.hours(6))
      {:ok, sesiones}
    end
  end

  def get_votaciones(diputado_id \\ nil) do
    year = Date.utc_today().year

    cache_key =
      if diputado_id, do: "votaciones_#{diputado_id}_#{year}", else: "votaciones_#{year}"

    with {:ok, cached} <- Cachex.get(:diputados_cache, cache_key) do
      case cached do
        nil ->
          fetch_and_cache_votaciones(year, cache_key, diputado_id)

        data ->
          {:ok, data}
      end
    else
      {:error, _} ->
        fetch_and_cache_votaciones(year, cache_key, diputado_id)
    end
  end

  defp fetch_and_cache_votaciones(year, cache_key, _diputado_id) do
    with {:ok, body} <-
           get_xml("#{@base_url}/WSSala.asmx/retornarVotacionesXAnno", params: [prmAnno: year]) do
      votaciones =
        body
        |> xpath(~x"//*[local-name()='Votacion']"l,
          id: ~x"./*[local-name()='Id']/text()"s,
          sesion_id: ~x"./*[local-name()='Sesion']/*[local-name()='Id']/text()"s,
          sesion_numero: ~x"./*[local-name()='Sesion']/*[local-name()='Numero']/text()"s,
          fecha: ~x"./*[local-name()='Sesion']/*[local-name()='FechaInicio']/text()"s,
          titulo: ~x"./*[local-name()='Materia']/text()"s,
          resultado: ~x"./*[local-name()='Resultado']/text()"s,
          quorum: ~x"./*[local-name()='Quorum']/text()"s,
          tipo: ~x"./*[local-name()='Tipo']/text()"s
        )
        |> Enum.map(fn v ->
          %{
            id: v.id,
            sesion_id: v.sesion_id,
            sesion_numero: v.sesion_numero,
            fecha: parse_date(v.fecha),
            titulo: v.titulo,
            resultado: v.resultado,
            quorum: v.quorum,
            tipo: v.tipo
          }
        end)
        |> Enum.sort_by(& &1.fecha, {:desc, Date})
        |> Enum.take(100)

      Cachex.put(:diputados_cache, cache_key, votaciones, ttl: :timer.hours(6))
      {:ok, votaciones}
    end
  end

  def get_comisiones() do
    cache_key = "comisiones"

    with {:ok, cached} <- Cachex.get(:diputados_cache, cache_key) do
      case cached do
        nil ->
          fetch_and_cache_comisiones(cache_key)

        data ->
          {:ok, data}
      end
    else
      {:error, _} ->
        fetch_and_cache_comisiones(cache_key)
    end
  end

  defp fetch_and_cache_comisiones(cache_key) do
    with {:ok, body} <- get_xml("#{@base_url}/WSComision.asmx/retornarComisiones") do
      comisiones =
        body
        |> xpath(~x"//*[local-name()='Comision']"l,
          id: ~x"./*[local-name()='Id']/text()"s,
          nombre: ~x"./*[local-name()='Nombre']/text()"s,
          tipo: ~x"./*[local-name()='Tipo']/text()"s
        )
        |> Enum.map(fn c -> %{id: c.id, nombre: c.nombre, tipo: c.tipo} end)

      Cachex.put(:diputados_cache, cache_key, comisiones, ttl: :timer.hours(24))
      {:ok, comisiones}
    end
  end

  def get_diputado_detail(diputado_id) do
    cache_key = "diputado_#{diputado_id}"

    with {:ok, cached} <- Cachex.get(:diputados_cache, cache_key) do
      case cached do
        nil ->
          fetch_and_cache_diputado_detail(diputado_id, cache_key)

        data ->
          {:ok, data}
      end
    else
      {:error, _} ->
        fetch_and_cache_diputado_detail(diputado_id, cache_key)
    end
  end

  defp fetch_and_cache_diputado_detail(diputado_id, cache_key) do
    result =
      with {:ok, body} <-
             get_xml("#{@base_url}/WSDiputado.asmx/retornarDiputado",
               params: [prmDiputadoId: diputado_id]
             ) do
        detail = parse_deputy_detail(body)
        Cachex.put(:diputados_cache, cache_key, detail, ttl: :timer.hours(12))
        {:ok, detail}
      end

    case result do
      {:ok, _} -> result
      _ -> {:error, :not_found}
    end
  end

  defp parse_deputy_detail(body) do
    body
    |> xpath(~x"//*[local-name()='Diputado']"l,
      id: ~x"./*[local-name()='Id']/text()"s,
      nombre: ~x"./*[local-name()='Nombre']/text()"s,
      nombre2: ~x"./*[local-name()='Nombre2']/text()"s,
      apellido_paterno: ~x"./*[local-name()='ApellidoPaterno']/text()"s,
      apellido_materno: ~x"./*[local-name()='ApellidoMaterno']/text()"s,
      fecha_nacimiento: ~x"./*[local-name()='FechaNacimiento']/text()"s,
      genero: ~x"./*[local-name()='Sexo']/text()"s,
      correo: ~x"./*[local-name()='Email']/text()"s
    )
    |> List.first()
    |> then(fn d ->
      %{
        id: d.id,
        nombre: full_name(d),
        nombre_completo: full_name(d),
        fecha_nacimiento: parse_date(d.fecha_nacimiento),
        genero: d.genero,
        correo: d.correo
      }
    end)
  end

  defp get_current_period do
    today = Date.utc_today()

    with {:ok, body} <- get_xml("#{@base_url}/WSLegislativo.asmx/retornarPeriodosLegislativos"),
         periods <- parse_periods(body),
         {:ok, period} <- find_period(periods, today) do
      active_period =
        if period.id == "11" do
          Enum.find(periods, fn p -> p.id == "10" end) || period
        else
          period
        end

      {:ok, active_period.id, {active_period.fecha_inicio, active_period.fecha_termino}}
    end
  end

  defp parse_periods(body) do
    body
    |> xpath(~x"//*[local-name()='PeriodoLegislativo']"l,
      id: ~x"./*[local-name()='Id']/text()"s,
      fecha_inicio: ~x"./*[local-name()='FechaInicio']/text()"s,
      fecha_termino: ~x"./*[local-name()='FechaTermino']/text()"s
    )
    |> Enum.map(fn p ->
      %{
        id: p.id,
        fecha_inicio: parse_date(p.fecha_inicio),
        fecha_termino: parse_date(p.fecha_termino)
      }
    end)
  end

  defp find_period(periods, date) do
    case Enum.find(periods, fn p ->
           Date.compare(p.fecha_inicio, date) != :gt and
             Date.compare(p.fecha_termino, date) != :lt
         end) do
      nil -> {:error, :period_not_found}
      p -> {:ok, p}
    end
  end

  defp active_in_period?(deputy, {start_date, period_end}) do
    start = parse_date(deputy.fecha_inicio)
    ends = parse_date(deputy.fecha_termino, period_end)
    Date.compare(start, period_end) != :gt and Date.compare(ends, start_date) != :lt
  end

  defp parse_deputy(d) do
    %{
      id: d.id,
      nombre: full_name(d),
      nombre_completo: full_name(d),
      partido: blank_to(d.partido, "IND"),
      partido_nombre: blank_to(d.partido_nombre, "Independiente"),
      distrito: parse_district(d.distrito_numero),
      region: nil,
      periodo: "2022-2026",
      estado: "Activo",
      cargo: parse_cargo(d.cargo),
      foto: nil
    }
  end

  defp full_name(d) do
    [d.nombre, d.nombre2, d.apellido_paterno, d.apellido_materno]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
  end

  defp parse_date(nil), do: Date.utc_today()
  defp parse_date(""), do: Date.utc_today()

  defp parse_date(date, _fallback) when is_binary(date) do
    date |> String.slice(0, 10) |> Date.from_iso8601!()
  rescue
    _ -> Date.utc_today()
  end

  defp parse_date(date) when is_binary(date) do
    date |> String.slice(0, 10) |> Date.from_iso8601!()
  rescue
    _ -> Date.utc_today()
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, _} -> num
      _ -> nil
    end
  end

  defp parse_district(nil), do: nil
  defp parse_district(""), do: nil
  defp parse_district(num), do: parse_int(num)

  defp parse_cargo(nil), do: "Diputado"
  defp parse_cargo(""), do: "Diputado"
  defp parse_cargo(c) when is_binary(c), do: if(String.trim(c) == "", do: "Diputado", else: c)

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  defp blank_to(nil, default), do: default
  defp blank_to("", default), do: default
  defp blank_to(val, _), do: val

  defp get_xml(url, opts \\ []) do
    opts = Keyword.put_new(opts, :headers, @default_headers)

    case Req.get(url, opts) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: s}} -> {:error, {:http_status, s}}
      {:error, r} -> {:error, r}
    end
  end
end
