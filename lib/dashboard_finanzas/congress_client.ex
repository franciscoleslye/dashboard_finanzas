defmodule DashboardFinanzas.CongressClient do
  import SweetXml
  require Logger

  @base_url "https://opendata.camara.cl/camaradiputados/WServices"
  @comun_base_url "https://opendata.camara.cl/camaradiputados/WServices/WSComun.asmx"
  @default_headers %{
    "user-agent" => "Mozilla/5.0",
    "accept" => "application/xml"
  }

  @old_api_base "https://opendata.camara.cl/wscamaradiputados.asmx"

  def obtener_diputados() do
    with {:ok, period_id, period_range} <- obtener_periodo_legislativo_actual(),
         cache_key <- "diputados_#{period_id}",
         {:ok, cached} <- Cachex.get(:congress_cache, cache_key) do
      case cached do
        nil ->
          with {:ok, distritos} <- fetch_distritos(),
               {:ok, regiones} <- fetch_regiones(),
               {:ok, diputados} <- fetch_diputados(period_id, period_range, distritos, regiones) do
            Cachex.put(:congress_cache, cache_key, diputados, ttl: :timer.hours(12))
            {:ok, diputados}
          end

        diputados ->
          {:ok, diputados}
      end
    else
      {:error, reason} ->
        Logger.warning("[CongressClient] Error fetching diputados: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def obtener_asistencias(_diputado_id) do
    obtener_asistencias_all()
  end

  def obtener_asistencias(), do: obtener_asistencias_all()

  def obtener_asistencias_all() do
    year = Date.utc_today().year
    cache_key = "asistencias_all_#{year}"

    with {:ok, cached} <- Cachex.get(:congress_cache, cache_key) do
      case cached do
        nil ->
          with {:ok, asistencia} <- fetch_asistencias_all(year) do
            Cachex.put(:congress_cache, cache_key, asistencia, ttl: :timer.hours(6))
            {:ok, asistencia}
          end

        asistencia ->
          {:ok, asistencia}
      end
    else
      {:error, reason} ->
        Logger.warning("[CongressClient] Error fetching asistencia: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def obtener_sesiones_recientes() do
    year = Date.utc_today().year
    cache_key = "sesiones_#{year}"

    with {:ok, cached} <- Cachex.get(:congress_cache, cache_key) do
      case cached do
        nil ->
          with {:ok, sesiones} <- fetch_sesiones_recientes(year) do
            Cachex.put(:congress_cache, cache_key, sesiones, ttl: :timer.hours(6))
            {:ok, sesiones}
          end

        sesiones ->
          {:ok, sesiones}
      end
    else
      {:error, reason} ->
        Logger.warning("[CongressClient] Error fetching sesiones: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def obtener_proyectos_recientes() do
    year = Date.utc_today().year
    cache_key = "proyectos_#{year}"

    with {:ok, cached} <- Cachex.get(:congress_cache, cache_key) do
      case cached do
        nil ->
          with {:ok, proyectos} <- fetch_proyectos_recientes(year) do
            Cachex.put(:congress_cache, cache_key, proyectos, ttl: :timer.hours(6))
            {:ok, proyectos}
          end

        proyectos ->
          {:ok, proyectos}
      end
    else
      {:error, reason} ->
        Logger.warning("[CongressClient] Error fetching proyectos: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp obtener_periodo_legislativo_actual() do
    today = Date.utc_today()

    with {:ok, body} <- get_xml("#{@base_url}/WSLegislativo.asmx/retornarPeriodosLegislativos"),
         periods <- parse_periodos(body),
         {:ok, period} <- find_period_for_date(periods, today) do
      active_period =
        if period.id == "11" do
          Enum.find(periods, fn p -> p.id == "10" end) || period
        else
          period
        end

      {:ok, active_period.id, {active_period.fecha_inicio, active_period.fecha_termino}}
    end
  end

  defp fetch_diputados(period_id, period_range, distritos, regiones) do
    with {:ok, body} <-
           get_xml("#{@base_url}/WSDiputado.asmx/retornarDiputadosXPeriodo",
             params: [prmPeriodoId: period_id]
           ) do
      diputados =
        body
        |> xpath(
          ~x"//*[local-name()='DiputadoPeriodo']"l,
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
        |> Enum.filter(&diputado_activo_en_periodo?(&1, period_range))
        |> Enum.map(fn diputados_data ->
          distrito_num = parse_distrito_num(diputados_data.distrito_numero)
          region = find_region_for_distrito(distrito_num, distritos, regiones)
          cargo = parse_cargo(diputados_data.cargo)

          %{
            id: diputados_data.id,
            nombre: full_name(diputados_data),
            nombre_completo: full_name(diputados_data),
            partido: blank_to(diputados_data.partido, "IND"),
            partido_nombre: blank_to(diputados_data.partido_nombre, "Independiente"),
            distrito: distrito_num,
            region: region,
            periodo: format_period(period_range),
            estado: "Activo",
            cargo: cargo,
            foto: nil,
            porcentaje: nil
          }
        end)

      {:ok, diputados}
    end
  end

  @region_mapping %{
    1 => "Tarapacá",
    2 => "Antofagasta",
    3 => "Atacama",
    4 => "Coquimbo",
    5 => "Valparaíso",
    6 => "Libertador General Bernardo O'Higgins",
    7 => "Maule",
    8 => "Biobío",
    9 => "Araucanía",
    10 => "Los Lagos",
    11 => "Aysén del General Carlos Ibáñez del Campo",
    12 => "Magallanes y Antártica Chilena",
    13 => "Región Metropolitana",
    14 => "Los Ríos",
    15 => "Arica y Parinacota",
    16 => "Ñuble"
  }

  @district_to_region %{
    1 => 1,
    2 => 1,
    3 => 2,
    4 => 2,
    5 => 3,
    6 => 3,
    7 => 4,
    8 => 4,
    9 => 4,
    10 => 4,
    11 => 5,
    12 => 5,
    13 => 5,
    14 => 5,
    15 => 5,
    16 => 5,
    17 => 5,
    18 => 5,
    19 => 13,
    20 => 13,
    21 => 13,
    22 => 13,
    23 => 13,
    24 => 13,
    25 => 6,
    26 => 6,
    27 => 7,
    28 => 7,
    29 => 7,
    30 => 7,
    31 => 8,
    32 => 8,
    33 => 8,
    34 => 8,
    35 => 8,
    36 => 8,
    37 => 8,
    38 => 9,
    39 => 9,
    40 => 9,
    41 => 9,
    42 => 16,
    43 => 16,
    44 => 10,
    45 => 10,
    46 => 10,
    47 => 10,
    48 => 11,
    49 => 12,
    50 => 13,
    51 => 13,
    52 => 13,
    53 => 14,
    54 => 14,
    55 => 15,
    56 => 15,
    57 => 10,
    58 => 10,
    59 => 13,
    60 => 13
  }

  defp find_region_for_distrito(nil, _distritos, _regiones), do: nil

  defp find_region_for_distrito(distrito_num, _distritos, _regiones) do
    case Map.get(@district_to_region, distrito_num) do
      nil -> nil
      region_num -> Map.get(@region_mapping, region_num)
    end
  end

  defp fetch_distritos() do
    cache_key = "distritos"

    with {:ok, cached} <- Cachex.get(:congress_cache, cache_key) do
      case cached do
        nil ->
          with {:ok, body} <- get_xml("#{@comun_base_url}/retornarDistritos") do
            distritos =
              body
              |> xpath(
                ~x"//*[local-name()='Distrito']"l,
                numero: ~x"./*[local-name()='Numero']/text()"s
              )
              |> Enum.map(fn d ->
                %{
                  numero: parse_int(d.numero),
                  primera_comuna: nil
                }
              end)

            Cachex.put(:congress_cache, cache_key, distritos, ttl: :timer.hours(24))
            {:ok, distritos}
          end

        distritos ->
          {:ok, distritos}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_regiones() do
    cache_key = "regiones"

    with {:ok, cached} <- Cachex.get(:congress_cache, cache_key) do
      case cached do
        nil ->
          with {:ok, body} <- get_xml("#{@comun_base_url}/retornarRegiones") do
            regiones =
              body
              |> xpath(
                ~x"//*[local-name()='Region']"l,
                numero: ~x"./*[local-name()='Numero']/text()"s,
                nombre: ~x"./*[local-name()='Nombre']/text()"s
              )
              |> Enum.map(fn r ->
                %{
                  numero: parse_int(r.numero),
                  nombre: r.nombre
                }
              end)

            Cachex.put(:congress_cache, cache_key, regiones, ttl: :timer.hours(24))
            {:ok, regiones}
          end

        regiones ->
          {:ok, regiones}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_asistencias(_diputado_id, _period_id) do
    {:ok, %{}}
  end

  defp fetch_asistencias_all(year) do
    with {:ok, sesiones} <- fetch_sesiones_recientes(year) do
      deputy_attendance =
        Enum.reduce(sesiones, %{}, fn sesion, acc ->
          case fetch_sesion_asistencia(sesion.id) do
            {:ok, asistentes} ->
              Enum.reduce(asistentes, acc, fn %{id: dip_id, asistio: asistio}, inner_acc ->
                current = Map.get(inner_acc, dip_id, %{asistencias: 0, sesiones: 0})

                Map.put(inner_acc, dip_id, %{
                  asistencias: current.asistencias + if(asistio, do: 1, else: 0),
                  sesiones: current.sesiones + 1
                })
              end)

            _ ->
              acc
          end
        end)

      attendance_map =
        Enum.map(deputy_attendance, fn {id, data} ->
          porcentaje =
            if data.sesiones > 0, do: round(data.asistencias / data.sesiones * 100), else: 0

          {id,
           %{
             asistencia: data.asistencias,
             inasistencias: data.sesiones - data.asistencias,
             porcentaje: porcentaje
           }}
        end)
        |> Map.new()

      {:ok, attendance_map}
    else
      {:error, reason} ->
        Logger.warning("[CongressClient] Error fetching all asistencia: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_sesion_asistencia(sesion_id) do
    with {:ok, body} <-
           get_xml("#{@base_url}/WSSala.asmx/retornarSesionAsistencia",
             params: [prmSesionId: sesion_id]
           ) do
      asistentes =
        body
        |> xpath(
          ~x"//*[local-name()='Asistencia']"l,
          dip_id: ~x"./*[local-name()='Diputado']/*[local-name()='Id']/text()"s,
          tipo: ~x"./*[local-name()='TipoAsistencia']/@Valor"s
        )
        |> Enum.map(fn a ->
          %{
            id: parse_int(a.dip_id),
            asistio: a.tipo == "1"
          }
        end)

      {:ok, asistentes}
    else
      {:error, _reason} ->
        {:ok, []}
    end
  end

  defp parse_distrito_num(nil), do: nil
  defp parse_distrito_num(""), do: nil
  defp parse_distrito_num(num), do: parse_int(num)

  defp find_region_for_distrito(nil, _distritos, _regiones), do: nil

  defp find_region_for_distrito(distrito_num, distritos, regiones) do
    case Enum.find(distritos, &(&1.numero == distrito_num)) do
      nil ->
        nil

      d ->
        case Enum.find(regiones, &(&1.numero == d.region_numero)) do
          nil -> nil
          r -> r.nombre
        end
    end
  end

  defp parse_cargo(nil), do: "Diputado"
  defp parse_cargo(""), do: "Diputado"

  defp parse_cargo(cargo) when is_binary(cargo) do
    case String.trim(cargo) do
      "" -> "Diputado"
      c -> c
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp fetch_sesiones_recientes(year) do
    with {:ok, body} <-
           get_xml("#{@base_url}/WSSala.asmx/retornarSesionesXAnno", params: [prmAnno: year]) do
      sesiones =
        body
        |> xpath(
          ~x"//*[local-name()='Sesion']"l,
          id: ~x"./*[local-name()='Id']/text()"s,
          numero: ~x"./*[local-name()='Numero']/text()"s,
          fecha_inicio: ~x"./*[local-name()='FechaInicio']/text()"s,
          tipo: ~x"./*[local-name()='Tipo']/text()"s,
          estado: ~x"./*[local-name()='Estado']/text()"s
        )
        |> Enum.map(fn sesion ->
          %{
            id: sesion.id,
            numero: sesion.numero,
            fecha: parse_datetime_date(sesion.fecha_inicio),
            tipo: sesion.tipo,
            estado: sesion.estado
          }
        end)
        |> Enum.sort_by(& &1.fecha, {:desc, Date})
        |> Enum.filter(fn s -> s.estado == "Celebrada" end)
        |> Enum.take(50)

      {:ok, sesiones}
    end
  end

  defp fetch_proyectos_recientes(year) do
    with {:ok, body} <-
           get_xml("#{@base_url}/WSLegislativo.asmx/retornarMocionesXAnno",
             params: [prmAnno: year]
           ) do
      proyectos =
        body
        |> xpath(
          ~x"//*[local-name()='ProyectoLey']"l,
          id: ~x"./*[local-name()='Id']/text()"s,
          boletin: ~x"./*[local-name()='NumeroBoletin']/text()"s,
          titulo: ~x"./*[local-name()='Nombre']/text()"s,
          fecha_ingreso: ~x"./*[local-name()='FechaIngreso']/text()"s,
          tipo: ~x"./*[local-name()='TipoIniciativa']/text()"s,
          camara_origen: ~x"./*[local-name()='CamaraOrigen']/text()"s
        )
        |> Enum.map(fn proyecto ->
          %{
            id: proyecto.id,
            boletin: proyecto.boletin,
            titulo: proyecto.titulo,
            fecha: parse_datetime_date(proyecto.fecha_ingreso),
            detalle:
              Enum.reject([proyecto.tipo, proyecto.camara_origen], &blank?/1) |> Enum.join(" • ")
          }
        end)
        |> Enum.sort_by(& &1.fecha, {:desc, Date})
        |> Enum.take(5)

      {:ok, proyectos}
    end
  end

  defp get_xml(url, opts \\ []) do
    req_opts =
      opts
      |> Keyword.put_new(:headers, @default_headers)
      |> Keyword.put_new(:decode_body, false)

    case Req.get(url, req_opts) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_periodos(body) do
    body
    |> xpath(
      ~x"//*[local-name()='PeriodoLegislativo']"l,
      id: ~x"./*[local-name()='Id']/text()"s,
      fecha_inicio: ~x"./*[local-name()='FechaInicio']/text()"s,
      fecha_termino: ~x"./*[local-name()='FechaTermino']/text()"s
    )
    |> Enum.map(fn period ->
      %{
        id: period.id,
        fecha_inicio: parse_datetime_date(period.fecha_inicio),
        fecha_termino: parse_datetime_date(period.fecha_termino)
      }
    end)
  end

  defp find_period_for_date(periods, date) do
    case Enum.find(
           periods,
           &(Date.compare(&1.fecha_inicio, date) != :gt and
               Date.compare(&1.fecha_termino, date) != :lt)
         ) do
      nil -> {:error, :period_not_found}
      period -> {:ok, period}
    end
  end

  defp diputado_activo_en_periodo?(diputado, {period_start, period_end}) do
    start_date = parse_datetime_date(diputado.fecha_inicio)
    end_date = parse_datetime_date(diputado.fecha_termino, period_end)

    Date.compare(start_date, period_end) != :gt and Date.compare(end_date, period_start) != :lt
  end

  defp parse_datetime_date(datetime, fallback \\ Date.utc_today())
  defp parse_datetime_date(nil, fallback), do: fallback
  defp parse_datetime_date("", fallback), do: fallback

  defp parse_datetime_date(datetime, _fallback) do
    datetime
    |> String.slice(0, 10)
    |> Date.from_iso8601!()
  end

  defp full_name(diputado) do
    [diputado.nombre, diputado.nombre2, diputado.apellido_paterno, diputado.apellido_materno]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
  end

  defp format_period({start_date, end_date}), do: "#{start_date.year}-#{end_date.year}"

  defp blank?(value), do: value in [nil, ""]
  defp blank_to(value, default) when value in [nil, ""], do: default
  defp blank_to(value, _default), do: value
end
