defmodule DashboardFinanzas.ClientSenadores do
  import SweetXml
  require Logger

  @base_url "https://opendata.camara.cl/camaradiputados/WServices"
  @comun_base_url "https://opendata.camara.cl/camaradiputados/WServices/WSComun.asmx"
  @senado_url "https://opendata.camara.cl/wssenado"
  @default_headers %{
    "user-agent" => "Mozilla/5.0",
    "accept" => "application/xml"
  }

  def get_senadores_vigentes() do
    cache_key = "senadores_vigentes"

    with {:ok, cached} <- Cachex.get(:senadores_cache, cache_key) do
      case cached do
        nil -> fetch_and_cache_senadores(cache_key)
        senators -> {:ok, senators}
      end
    else
      {:error, _} -> fetch_and_cache_senadores(cache_key)
    end
  end

  defp fetch_and_cache_senadores(cache_key) do
    with {:ok, body} <-
           get_xml("#{@base_url}/WSSenador.asmx/retornarSenadoresXPeriodo",
             params: [prmPeriodoId: "11"]
           ) do
      senators =
        body
        |> xpath(~x"//*[local-name()='SenadorPeriodo']"l,
          id: ~x"./*[local-name()='Senador']/*[local-name()='Id']/text()"s,
          nombre: ~x"./*[local-name()='Senador']/*[local-name()='Nombre']/text()"s,
          nombre2: ~x"./*[local-name()='Senador']/*[local-name()='Nombre2']/text()"s,
          apellido_paterno:
            ~x"./*[local-name()='Senador']/*[local-name()='ApellidoPaterno']/text()"s,
          apellido_materno:
            ~x"./*[local-name()='Senador']/*[local-name()='ApellidoMaterno']/text()"s,
          fecha_inicio: ~x"./*[local-name()='FechaInicio']/text()"s,
          fecha_termino: ~x"./*[local-name()='FechaTermino']/text()"s,
          partido:
            ~x"./*[local-name()='Senador']/*[local-name()='Militancias']/*[local-name()='Militancia'][last()]/*[local-name()='Partido']/*[local-name()='Alias']/text()"s,
          partido_nombre:
            ~x"./*[local-name()='Senador']/*[local-name()='Militancias']/*[local-name()='Militancia'][last()]/*[local-name()='Partido']/*[local-name()='Nombre']/text()"s,
          region:
            ~x"./*[local-name()='Senador']/*[local-name()='Region']/*[local-name()='Nombre']/text()"s,
          cargo: ~x"./*[local-name()='Cargo']/text()"s
        )
        |> Enum.filter(&senator_active?/1)
        |> Enum.map(&parse_senator/1)
        |> Enum.sort_by(& &1.nombre)

      Cachex.put(:senadores_cache, cache_key, senators, ttl: :timer.hours(12))
      {:ok, senators}
    else
      {:error, reason} ->
        Logger.warning("[ClientSenadores] Error fetching senators: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get_sesiones_senado(year \\ nil) do
    year = year || Date.utc_today().year
    cache_key = "sesiones_senado_#{year}"

    with {:ok, cached} <- Cachex.get(:senadores_cache, cache_key) do
      case cached do
        nil -> fetch_and_cache_sesiones(year, cache_key)
        data -> {:ok, data}
      end
    else
      {:error, _} -> fetch_and_cache_sesiones(year, cache_key)
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
        |> Enum.take(30)

      Cachex.put(:senadores_cache, cache_key, sesiones, ttl: :timer.hours(6))
      {:ok, sesiones}
    end
  end

  def get_diario_sesion(sesion_id \\ nil) do
    cache_key = if sesion_id, do: "diario_sesion_#{sesion_id}", else: "diario_sesion_latest"

    with {:ok, cached} <- Cachex.get(:senadores_cache, cache_key) do
      case cached do
        nil -> fetch_and_cache_diario(sesion_id, cache_key)
        data -> {:ok, data}
      end
    else
      {:error, _} -> fetch_and_cache_diario(sesion_id, cache_key)
    end
  end

  defp fetch_and_cache_diario(sesion_id, cache_key) do
    sesion_id = sesion_id || "4755"

    with {:ok, body} <-
           get_xml("#{@base_url}/WSSala.asmx/retornarSesionDetalle",
             params: [prmSesionId: sesion_id]
           ) do
      diario = parse_diario_sesion(body)

      Cachex.put(:senadores_cache, cache_key, diario, ttl: :timer.hours(12))
      {:ok, diario}
    else
      {:error, reason} ->
        Logger.warning("[ClientSenadores] Error fetching diario: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_diario_sesion(body) do
    sesion =
      body
      |> xpath(~x"//*[local-name()='Sesion']"l,
        id: ~x"./*[local-name()='Id']/text()"s,
        numero: ~x"./*[local-name()='Numero']/text()"s,
        fecha: ~x"./*[local-name()='FechaInicio']/text()"s,
        tipo: ~x"./*[local-name()='Tipo']/text()"s
      )
      |> List.first()

    materias =
      body
      |> xpath(~x"//*[local-name()='Materia']"l,
        id: ~x"./*[local-name()='Id']/text()"s,
        titulo: ~x"./*[local-name()='Nombre']/text()"s,
        tipo: ~x"./*[local-name()='TipoIniciativa']/text()"s,
        estado: ~x"./*[local-name()='Estado']/text()"s
      )

    %{
      sesion:
        sesion &&
          %{
            id: sesion.id,
            numero: sesion.numero,
            fecha: parse_date(sesion.fecha),
            tipo: sesion.tipo
          },
      materias:
        Enum.map(materias, fn m ->
          %{
            id: m.id,
            titulo: m.titulo,
            tipo: m.tipo,
            estado: m.estado
          }
        end)
    }
  end

  def get_comisiones_vigentes() do
    cache_key = "comisiones_vigentes"

    with {:ok, cached} <- Cachex.get(:senadores_cache, cache_key) do
      case cached do
        nil -> fetch_and_cache_comisiones(cache_key)
        data -> {:ok, data}
      end
    else
      {:error, _} -> fetch_and_cache_comisiones(cache_key)
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

      Cachex.put(:senadores_cache, cache_key, comisiones, ttl: :timer.hours(24))
      {:ok, comisiones}
    end
  end

  def get_comision_detail(comision_id) do
    cache_key = "comision_#{comision_id}"

    result =
      with {:ok, cached} <- Cachex.get(:senadores_cache, cache_key) do
        case cached do
          nil -> fetch_and_cache_comision_detail(comision_id, cache_key)
          data -> {:ok, data}
        end
      else
        {:error, _} -> fetch_and_cache_comision_detail(comision_id, cache_key)
      end

    result
  end

  defp fetch_and_cache_comision_detail(comision_id, cache_key) do
    with {:ok, body} <-
           get_xml("#{@base_url}/WSComision.asmx/retornarComision",
             params: [prmComisionId: comision_id]
           ) do
      comision = parse_comision_detail(body)
      Cachex.put(:senadores_cache, cache_key, comision, ttl: :timer.hours(12))
      {:ok, comision}
    end
  end

  defp parse_comision_detail(body) do
    info =
      body
      |> xpath(~x"//*[local-name()='Comision']"l,
        id: ~x"./*[local-name()='Id']/text()"s,
        nombre: ~x"./*[local-name()='Nombre']/text()"s,
        tipo: ~x"./*[local-name()='Tipo']/text()"s
      )
      |> List.first()

    miembros =
      body
      |> xpath(~x"//*[local-name()='Integrante']"l,
        id: ~x"./*[local-name()='Parlamentario']/*[local-name()='Id']/text()"s,
        nombre: ~x"./*[local-name()='Parlamentario']/*[local-name()='Nombre']/text()"s,
        cargo: ~x"./*[local-name()='Cargo']/text()"s
      )

    sesiones =
      body
      |> xpath(~x"//*[local-name()='SesionComision']"l,
        id: ~x"./*[local-name()='Id']/text()"s,
        numero: ~x"./*[local-name()='Numero']/text()"s,
        fecha: ~x"./*[local-name()='FechaInicio']/text()"s,
        estado: ~x"./*[local-name()='Estado']/text()"s
      )

    %{
      info: info && %{id: info.id, nombre: info.nombre, tipo: info.tipo},
      miembros: Enum.map(miembros, fn m -> %{id: m.id, nombre: m.nombre, cargo: m.cargo} end),
      sesiones_recientes:
        Enum.take(
          Enum.map(sesiones, fn s ->
            %{
              id: s.id,
              numero: s.numero,
              fecha: parse_date(s.fecha),
              estado: s.estado
            }
          end)
          |> Enum.sort_by(& &1.fecha, {:desc, Date}),
          10
        )
    }
  end

  def get_asistencia_senado(year \\ nil) do
    year = year || Date.utc_today().year
    cache_key = "asistencia_senado_#{year}"

    result =
      with {:ok, cached} <- Cachex.get(:senadores_cache, cache_key) do
        case cached do
          nil -> fetch_and_cache_asistencia(year, cache_key)
          data -> {:ok, data}
        end
      else
        {:error, _} -> fetch_and_cache_asistencia(year, cache_key)
      end

    result
  end

  defp fetch_and_cache_asistencia(year, cache_key) do
    with {:ok, sesiones} <- get_sesiones_senado(year) do
      sesiones_ids =
        Enum.filter(sesiones, fn s -> s.estado == "Celebrada" end)
        |> Enum.map(& &1.id)
        |> Enum.take(30)

      attendance =
        Enum.reduce(sesiones_ids, %{}, fn sesion_id, acc ->
          case fetch_sesion_asistencia(sesion_id) do
            {:ok, attendees} ->
              Enum.reduce(attendees, acc, fn %{id: sen_id, tipo: tipo}, inner_acc ->
                current = Map.get(inner_acc, sen_id, %{asistencias: 0, sesiones: 0})
                asistio = tipo == "1"

                Map.put(inner_acc, sen_id, %{
                  asistencias: current.asistencias + if(asistio, do: 1, else: 0),
                  sesiones: current.sesiones + 1
                })
              end)

            _ ->
              acc
          end
        end)

      data =
        Enum.map(attendance, fn {id, d} ->
          pct = if(d.sesiones > 0, do: round(d.asistencias / d.sesiones * 100), else: 0)

          {id,
           %{
             asistencia: d.asistencias,
             inasistencias: d.sesiones - d.asistencias,
             porcentaje: pct
           }}
        end)
        |> Map.new()

      Cachex.put(:senadores_cache, cache_key, data, ttl: :timer.hours(6))
      {:ok, data}
    end
  end

  defp fetch_sesion_asistencia(sesion_id) do
    with {:ok, body} <-
           get_xml("#{@base_url}/WSSala.asmx/retornarSesionAsistencia",
             params: [prmSesionId: sesion_id]
           ) do
      attendees =
        body
        |> xpath(~x"//*[local-name()='Asistencia']"l,
          id: ~x"./*[local-name()='Senador']/*[local-name()='Id']/text()"s,
          tipo: ~x"./*[local-name()='TipoAsistencia']/@Valor"s
        )
        |> Enum.map(fn a -> %{id: parse_int(a.id), tipo: a.tipo} end)

      {:ok, attendees}
    else
      _ -> {:ok, []}
    end
  end

  defp senator_active?(s) do
    start = parse_date(s.fecha_inicio)
    ends = parse_date(s.fecha_termino)
    today = Date.utc_today()
    Date.compare(start, today) != :gt and Date.compare(ends, today) != :lt
  end

  defp parse_senator(s) do
    %{
      id: s.id,
      nombre: full_name(s),
      nombre_completo: full_name(s),
      partido: blank_to(s.partido, "IND"),
      partido_nombre: blank_to(s.partido_nombre, "Independiente"),
      region: s.region,
      periodo: "2022-2026",
      estado: "Activo",
      cargo: parse_cargo(s.cargo),
      foto: nil
    }
  end

  defp full_name(s) do
    [s.nombre, s.nombre2, s.apellido_paterno, s.apellido_materno]
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

  defp parse_date(date) when is_binary(date), do: parse_date(date, nil)

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, _} -> num
      _ -> nil
    end
  end

  defp parse_cargo(nil), do: "Senador"
  defp parse_cargo(""), do: "Senador"
  defp parse_cargo(c) when is_binary(c), do: if(String.trim(c) == "", do: "Senador", else: c)

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
