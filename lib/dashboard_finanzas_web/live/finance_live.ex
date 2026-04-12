defmodule DashboardFinanzasWeb.FinanceLive do
  use DashboardFinanzasWeb, :live_view
  alias DashboardFinanzas.{CmfClient, BankData}

  @impl true
  def mount(_params, _session, socket) do
    {data, indicators_error} = load_indicators()
    {uf_history, history_error} = load_uf_history()

    banks =
      case Cachex.get(:bank_cache, "all_banks") do
        {:ok, nil} -> []
        {:ok, banks_data} -> banks_data
        {:error, _} -> []
      end

    state =
      case Cachex.get(:bank_cache, "last_updated") do
        {:ok, ts} when ts != nil -> %{last_updated: ts}
        _ -> %{last_updated: nil}
      end

    socket =
      if banks == [] do
        send(self(), :fetch_banks)
        socket
      else
        socket
      end

    {:ok,
     assign(socket,
       uf: data.uf,
       dolar: data.dolar,
       euro: data.euro,
       utm: data.utm,
       ipc: data.ipc,
       uf_history: uf_history,
       uf_range: 365,
       banks: sort_banks_by_score(banks),
       selected_bank: if(banks != [], do: hd(sort_banks_by_score(banks)), else: nil),
       refreshing: false,
       loading_banks: banks == [],
       last_updated: state.last_updated,
       indicators_error: indicators_error,
       history_error: history_error,
       bank_error: nil
     )}
  end

  @impl true
  def handle_info(:refresh_banks, socket) do
    banks =
      case Cachex.get(:bank_cache, "all_banks") do
        {:ok, nil} -> []
        {:ok, data} -> data
        _ -> []
      end

    {:noreply,
     assign(socket,
       banks: sort_banks_by_score(banks),
       selected_bank: if(banks != [], do: hd(sort_banks_by_score(banks)), else: nil),
       loading_banks: false,
       last_updated: DateTime.utc_now(),
       bank_error:
         if(banks == [], do: "No se encontraron datos bancarios disponibles.", else: nil)
     )}
  end

  @impl true
  def handle_info(:fetch_banks, socket) do
    with {:ok, {year, month}} <- BankData.periodo_disponible_actual(),
         {:ok, banks_data} <- BankData.obtener_todos_bancos_con_datos(year, month) do
      {:noreply,
       socket
       |> assign(
         banks: sort_banks_by_score(banks_data),
         selected_bank: if(banks_data != [], do: hd(sort_banks_by_score(banks_data)), else: nil),
         loading_banks: false,
         refreshing: false,
         bank_error:
           if(banks_data == [], do: "No se encontraron datos bancarios disponibles.", else: nil)
       )
       |> put_flash(:info, "Datos bancarios actualizados")}
    else
      {:error, reason} ->
        message = format_data_error(reason, "No fue posible cargar datos bancarios.")

        {:noreply,
         socket
         |> assign(loading_banks: false, refreshing: false, bank_error: message)
         |> put_flash(:error, message)}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    send(self(), :fetch_banks)

    {data, indicators_error} = load_indicators()
    {uf_history, history_error} = load_uf_history()

    {:noreply,
     socket
     |> assign(refreshing: true)
     |> assign(
       uf: data.uf,
       dolar: data.dolar,
       euro: data.euro,
       utm: data.utm,
       ipc: data.ipc,
       uf_history: uf_history,
       uf_range: socket.assigns[:uf_range] || 30,
       indicators_error: indicators_error,
       history_error: history_error
     )}
  end

  @impl true
  def handle_event("select_bank", %{"code" => code}, socket) do
    selected_bank = Enum.find(socket.assigns.banks, fn b -> b.code == code end)
    {:noreply, assign(socket, selected_bank: selected_bank)}
  end

  @impl true
  def handle_event("set_uf_range", %{"range" => range}, socket) do
    {:noreply, assign(socket, uf_range: String.to_integer(range))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-slate-900 via-blue-950 to-slate-900 p-fluid-4 overflow-x-hidden">
      <div class="w-full max-w-[1920px] mx-auto">
        <div class="flex justify-between items-center mb-fluid-6">
          <div class="text-center flex-1">
            <div class="flex items-center justify-center gap-3 mb-2">
              <div class="w-12 h-12 bg-sky-600 rounded-fluid flex items-center justify-center">
                <.icon name="hero-chart-bar-solid" class="w-7 h-7 text-white" />
              </div>
              <h1 class="text-fluid-3xl font-bold text-white tracking-tight">Chilehoy.org</h1>
            </div>
            <p class="text-fluid-sm text-sky-300">
              Indicadores Económicos y Estadísticas Bancarias de Chile
            </p>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-fluid-6 mb-fluid-8">
          <div class="lg:col-span-1 space-y-6">
            <.section_title title="Indicadores Monetarios" />
            <.error_banner :if={@indicators_error} message={@indicators_error} />
            <.error_banner :if={@history_error} message={@history_error} />
            <.indicator_grid
              uf={@uf}
              dolar={@dolar}
              euro={@euro}
              utm={@utm}
              ipc={@ipc}
            />
            <.chart_placeholder uf_history={@uf_history} uf_range={@uf_range} />
            <.bank_detail_section banks={@banks} selected_bank={@selected_bank} />
          </div>
          <div class="lg:col-span-2">
            <.section_title title="Sistema Bancario - Resumen Comparativo" />
            <.error_banner :if={@bank_error} message={@bank_error} />
            <.bank_comparison_section banks={@banks} loading={@loading_banks} />
          </div>
        </div>

        <.refresh_button refreshing={@refreshing} />
      </div>
    </div>
    """
  end

  defp section_title(assigns) do
    ~H"""
    <div class="flex items-center gap-3 mb-fluid-4 mt-fluid-8">
      <div class="h-px flex-1 bg-gradient-to-r from-transparent via-[#52307E]/50 to-transparent">
      </div>
      <h2 class="text-fluid-lg font-semibold text-white/80 uppercase tracking-wider">{@title}</h2>
      <div class="h-px flex-1 bg-gradient-to-r from-transparent via-[#52307E]/50 to-transparent">
      </div>
    </div>
    """
  end

  attr :message, :string, required: true

  defp error_banner(assigns) do
    ~H"""
    <div class="mb-4 rounded-xl border border-amber-400/20 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
      {@message}
    </div>
    """
  end

  defp indicator_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      <.indicator_card
        label="Unidad de Fomento"
        symbol="UF"
        value={@uf.valor}
        date={@uf.fecha}
        icon="hero-calculator"
        color="blue"
      />
      <.indicator_card
        label="Dólar Observado"
        symbol="USD"
        value={@dolar.valor}
        date={@dolar.fecha}
        icon="hero-banknotes"
        color="green"
      />
      <.indicator_card
        label="Euro"
        symbol="EUR"
        value={@euro.valor}
        date={@euro.fecha}
        icon="hero-globe-europe-africa"
        color="purple"
      />
      <.indicator_card
        label="Unidad Tributaria Mensual"
        symbol="UTM"
        value={@utm.valor}
        date={@utm.fecha}
        icon="hero-scale"
        color="amber"
      />
      <.indicator_card
        label="Índice de Precios al Consumidor"
        symbol="IPC"
        value={@ipc.valor}
        date={@ipc.fecha}
        icon="hero-arrow-trending-up"
        color="rose"
        suffix="%"
      />
      <.trend_summary uf={@uf} dolar={@dolar} />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :symbol, :string, required: true
  attr :value, :any, required: true
  attr :date, :any, required: true
  attr :icon, :string, required: true
  attr :color, :string, default: "blue"
  attr :suffix, :string, default: "$"

  defp indicator_card(assigns) do
    ~H"""
    <div class={"relative overflow-hidden rounded-2xl p-fluid-6 shadow-lg backdrop-blur-xl #{color_class(@color)}"}>
      <div class="absolute top-0 right-0 w-24 h-24 opacity-10 transform translate-x-6 -translate-y-6">
        <.icon name={@icon} class="w-full h-full" />
      </div>
      <div class="relative">
        <div class="flex items-center gap-2 mb-3">
          <div class={"w-8 h-8 rounded-lg flex items-center justify-center #{icon_bg_class(@color)}"}>
            <.icon name={@icon} class={"w-4 h-4 #{icon_text_class(@color)}"} />
          </div>
          <div>
            <p class={"text-fluid-xs font-semibold uppercase tracking-wider #{text_secondary_class(@color)}"}>
              {@symbol}
            </p>
            <p class="text-fluid-sm font-medium text-white/80">{@label}</p>
          </div>
        </div>
        <div class="flex items-end justify-between">
          <div>
            <p class="text-fluid-2xl font-bold text-white tracking-tight">
              {if @suffix == "$", do: "$"}{format_number(@value)}{if @suffix == "%", do: "%"}
            </p>
            <p class="text-fluid-xs text-white/50 mt-1">
              {if @symbol in ~w[USD EUR], do: format_date_today(), else: format_date(@date)}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :uf, :any, required: true
  attr :dolar, :any, required: true

  defp trend_summary(assigns) do
    ~H"""
    <div class="relative overflow-hidden rounded-2xl bg-gradient-to-br from-indigo-600 to-purple-700 p-fluid-6 shadow-lg">
      <div class="absolute top-0 right-0 w-32 h-32 opacity-10 transform translate-x-8 -translate-y-8">
        <.icon name="hero-sparkles" class="w-full h-full text-white" />
      </div>
      <div class="relative">
        <p class="text-indigo-200 text-fluid-xs font-semibold uppercase tracking-wider mb-3">
          Resumen del Día
        </p>
        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <span class="text-white/70 text-fluid-sm">UF vs Dólar</span>
            <span class="text-white font-semibold">
              {calculate_ratio(@uf.valor, @dolar.valor)} UF/USD
            </span>
          </div>
          <div class="h-px bg-white/10"></div>
          <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-1 md:gap-0">
            <span class="text-white/70 text-fluid-sm">Fecha actual</span>
            <span class="text-white font-semibold">{format_date_today()}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :banks, :any, required: true
  attr :loading, :boolean, required: true

  defp bank_comparison_section(assigns) do
    ~H"""
    <%= if @loading do %>
      <div class="bg-white/5 backdrop-blur-xl rounded-2xl p-6 border border-white/10 text-center">
        <div class="flex items-center justify-center gap-3">
          <div class="animate-spin w-6 h-6 border-2 border-blue-500 border-t-transparent rounded-full">
          </div>
          <p class="text-white/70">Cargando datos bancarios...</p>
        </div>
      </div>
    <% else %>
      <%= if @banks == [] do %>
        <div class="bg-white/5 backdrop-blur-xl rounded-2xl p-6 border border-white/10 text-center text-white/60">
          No hay datos bancarios disponibles para el último período informado por la CMF.
        </div>
      <% else %>
        <.bank_comparison_table banks={@banks} />
      <% end %>
    <% end %>
    """
  end

  attr :banks, :any, required: true

  defp bank_comparison_table(assigns) do
    ~H"""
    <div class="bg-white/5 backdrop-blur-xl rounded-2xl overflow-x-auto border border-white/10">
      <table class="w-full">
        <thead class="bg-white/10">
          <tr>
            <th class="px-4 py-3 text-left text-xs font-semibold text-white/70 uppercase">Banco</th>
            <th class="px-4 py-3 text-right text-xs font-semibold text-white/70 uppercase">
              Activos
            </th>
            <th class="px-4 py-3 text-right text-xs font-semibold text-white/70 uppercase">
              Pasivos
            </th>
            <th class="px-4 py-3 text-right text-xs font-semibold text-white/70 uppercase">
              Resultado Neto
            </th>
            <th class="px-4 py-3 text-center text-xs font-semibold text-white/70 uppercase">
              Margen Neto
            </th>
            <th class="px-4 py-3 text-center text-xs font-semibold text-white/70 uppercase">
              Solvencia
            </th>
            <th class="px-4 py-3 text-center text-xs font-semibold text-white/70 uppercase">Score</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-white/5">
          <%= for bank <- @banks do %>
            <tr class="hover:bg-white/5 transition-colors">
              <td class="px-4 py-3 text-sm font-medium text-white">{format_bank_name(bank.name)}</td>
              <td class="px-4 py-3 text-sm text-right text-sky-300">
                {if bank.balance, do: "$#{format_full(bank.balance.activos)}", else: "-"}
              </td>
              <td class="px-4 py-3 text-sm text-right text-orange-300">
                {if bank.balance, do: "$#{format_full(bank.balance.pasivos)}", else: "-"}
              </td>
              <td class="px-4 py-3 text-sm text-right font-semibold">
                <%= if bank.resultados do %>
                  <span class={
                    if Decimal.compare(bank.resultados.resultado, Decimal.new(0)) == :gt,
                      do: "text-emerald-400",
                      else: "text-rose-400"
                  }>
                    ${format_full(bank.resultados.resultado)}
                  </span>
                <% else %>
                  -
                <% end %>
              </td>
              <td class="px-4 py-3 text-sm text-center">
                <%= if mn = margen_neto(bank) do %>
                  <span class="text-sky-300">{Decimal.to_float(mn)}%</span>
                <% else %>
                  -
                <% end %>
              </td>
              <td class="px-4 py-3 text-sm text-center">
                <%= if sol = solvencia(bank) do %>
                  <span class="text-emerald-300">{Decimal.to_float(sol)}</span>
                <% else %>
                  -
                <% end %>
              </td>
              <td class="px-4 py-3 text-sm text-center">
                <%= if score = calculate_health_score(bank) do %>
                  <span class={health_score_color(score)}>{score}/100</span>
                  <div class="text-xs text-white/50 mt-0.5">{calculate_health_label(score)}</div>
                <% else %>
                  -
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  attr :banks, :any, required: true
  attr :selected_bank, :any, required: true

  defp bank_detail_section(assigns) do
    ~H"""
    <%= if @banks != [] && @selected_bank do %>
      <.section_title title="Detalle por Banco" />
      <.bank_selector banks={@banks} selected_bank={@selected_bank} />
      <.bank_detail bank={@selected_bank} />
    <% end %>
    """
  end

  attr :banks, :any, required: true
  attr :selected_bank, :any, required: true

  defp bank_selector(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-1.5 mb-4">
      <%= for bank <- @banks do %>
        <button
          phx-click="select_bank"
          phx-value-code={bank.code}
          class={"px-2 py-1.5 rounded-lg text-xs font-medium transition-all whitespace-nowrap #{if @selected_bank && @selected_bank.code == bank.code, do: "bg-sky-500 text-white", else: "bg-white/10 text-white/70 hover:bg-white/20"}"}
        >
          {format_bank_name(bank.name)}
        </button>
      <% end %>
    </div>
    """
  end

  attr :bank, :any, required: true

  defp bank_detail(assigns) do
    assigns =
      assign(
        assigns,
        :resultado_color,
        if assigns.bank[:resultados] &&
             Decimal.compare(assigns.bank.resultados.resultado, Decimal.new(0)) == :gt do
          "text-emerald-300"
        else
          "text-rose-300"
        end
      )

    ~H"""
    <div class="bg-white/5 backdrop-blur-xl rounded-2xl p-6 border border-white/10 mb-8 overflow-hidden">
      <div class="mb-6">
        <h3 class="text-xl font-bold text-white">{format_bank_name(@bank.name)}</h3>
        <p class="text-white/60 text-sm">
          {if @bank.balance,
            do: format_month_year(@bank.balance.year, @bank.balance.month),
            else: "Balance Mensual"}
        </p>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-2 md:gap-4">
        <div class="bg-gradient-to-br from-sky-600/20 to-indigo-700/20 rounded-xl p-2 md:p-3">
          <p class="text-sky-300 text-[10px] md:text-xs font-medium uppercase tracking-wider mb-1">
            Balance
          </p>
          <div class="space-y-1">
            <div>
              <p class="text-white/60 text-[10px]">Activos</p>
              <p class="text-[9px] md:text-[10px] lg:text-xs font-bold text-white">
                {if @bank.balance, do: "$#{format_full(@bank.balance.activos)}", else: "-"}
              </p>
            </div>
            <div>
              <p class="text-white/60 text-[10px]">Pasivos</p>
              <p class="text-[9px] md:text-[10px] lg:text-xs font-bold text-white">
                {if @bank.balance, do: "$#{format_full(@bank.balance.pasivos)}", else: "-"}
              </p>
            </div>
          </div>
        </div>

        <div class="bg-gradient-to-br from-orange-600/20 to-red-700/20 rounded-xl p-2 md:p-3">
          <p class="text-orange-300 text-[10px] md:text-xs font-medium uppercase tracking-wider mb-1">
            Resultado
          </p>
          <div class="grid grid-cols-1 gap-1">
            <div>
              <p class="text-white/60 text-[10px]">Ingresos</p>
              <p class="text-[9px] md:text-[10px] lg:text-xs font-bold text-white">
                {if @bank.resultados, do: "$#{format_full(@bank.resultados.ingresos)}", else: "-"}
              </p>
            </div>
            <div>
              <p class="text-white/60 text-[10px]">Gastos</p>
              <p class="text-[9px] md:text-[10px] lg:text-xs font-bold text-white">
                {if @bank.resultados, do: "-$#{format_full_abs(@bank.resultados.gastos)}", else: "-"}
              </p>
            </div>
          </div>
        </div>

        <div class="bg-gradient-to-br from-emerald-600/20 to-green-700/20 rounded-xl p-2 md:p-3 flex flex-col justify-center">
          <p class="text-emerald-300 text-[10px] md:text-xs font-medium uppercase tracking-wider mb-1">
            Resultado Neto
          </p>
          <p class={"text-xs md:text-sm lg:text-base font-bold #{@resultado_color}"}>
            {if @bank.resultados, do: "$ #{format_full(@bank.resultados.resultado)}", else: "-"}
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp chart_placeholder(assigns) do
    range = Map.get(assigns, :uf_range, 30)
    history = assigns[:uf_history] || []

    data =
      case range do
        7 -> Enum.take(history, -7)
        30 -> Enum.take(history, -30)
        365 -> Enum.take(history, -365)
        _ -> Enum.take(history, -30)
      end

    {min_val, max_val} =
      Enum.reduce(data, {nil, nil}, fn entry, {min, max} ->
        val = Decimal.to_float(entry.valor)
        {min(min || val, val), max(max || val, val)}
      end)

    svg_data =
      if min_val && max_val && length(data) > 0 do
        range = max_val - min_val
        width = 100
        height = 60
        padding = 5

        points =
          Enum.with_index(data)
          |> Enum.map(fn {entry, i} ->
            val = Decimal.to_float(entry.valor)
            x = if(length(data) == 1, do: width / 2, else: i * width / max(length(data) - 1, 1))
            y = if(range == 0, do: height / 2, else: height - (val - min_val) / range * height)
            {x, y, entry.valor, entry.fecha}
          end)

        points_str =
          Enum.map_join(points, " ", fn {x, y, _, _} ->
            "#{Float.round(x, 1)},#{Float.round(y, 1)}"
          end)

        %{
          points: points_str,
          data_points: points,
          data_dates: Enum.map(points, fn {_, _, _, date} -> date end),
          data_values: Enum.map(points, fn {_, _, valor, _} -> Decimal.to_float(valor) end),
          min_val: Decimal.new("#{min_val}"),
          max_val: Decimal.new("#{max_val}"),
          range: Decimal.new("#{range}"),
          first_val: hd(data).valor,
          last_val: List.last(data).valor,
          first_date: hd(data).fecha,
          last_date: List.last(data).fecha
        }
      else
        nil
      end

    assigns =
      assigns
      |> assign(:uf_chart_data, data)
      |> assign(:uf_svg, svg_data)

    ~H"""
    <div class="bg-white/5 backdrop-blur-xl rounded-2xl p-fluid-6 mb-fluid-8 border border-white/10">
      <div class="flex items-center justify-between mb-fluid-6">
        <div>
          <h3 class="text-white font-semibold text-fluid-lg">Historial UF</h3>
        </div>
        <div class="flex gap-2">
          <button
            phx-click="set_uf_range"
            phx-value-range="30"
            class={"px-3 py-1.5 text-fluid-sm rounded-lg transition #{if @uf_range == 30, do: "bg-sky-500 text-white", else: "bg-white/10 text-white/70 hover:bg-white/20"}"}
          >
            30D
          </button>
          <button
            phx-click="set_uf_range"
            phx-value-range="365"
            class={"px-3 py-1.5 text-fluid-sm rounded-lg transition #{if @uf_range == 365, do: "bg-sky-500 text-white", else: "bg-white/10 text-white/70 hover:bg-white/20"}"}
          >
            1A
          </button>
        </div>
      </div>
      <%= if @uf_svg do %>
        <div
          class="relative group"
          id="uf-chart"
          phx-hook="UfChartHover"
          data-points={encode_uf_data(@uf_svg.data_points)}
          data-dates={encode_uf_dates(@uf_svg.data_dates)}
          data-values={encode_uf_values(@uf_svg.data_values)}
        >
          <svg viewBox="0 0 100 65" class="w-full h-24" preserveAspectRatio="none">
            <defs>
              <linearGradient id="ufGradient" x1="0%" y1="0%" x2="0%" y2="100%">
                <stop offset="0%" stop-color="rgb(34, 211, 238)" stop-opacity="0.3" />
                <stop offset="100%" stop-color="rgb(34, 211, 238)" stop-opacity="0" />
              </linearGradient>
              <filter id="ufGlow">
                <feGaussianBlur stdDeviation="0.3" result="coloredBlur" />
                <feMerge>
                  <feMergeNode in="coloredBlur" />
                  <feMergeNode in="SourceGraphic" />
                </feMerge>
              </filter>
            </defs>

            <%= for i <- 1..4 do %>
              <line
                x1="0"
                y1={i * 15}
                x2="100"
                y2={i * 15}
                stroke="rgba(255,255,255,0.08)"
                stroke-width="0.3"
              />
            <% end %>

            <polygon
              points={"0,60 #{@uf_svg.points} 100,60"}
              fill="url(#ufGradient)"
              class="opacity-50"
            />
            <polyline
              points={@uf_svg.points}
              fill="none"
              stroke="#0ea5e9"
              stroke-width="1.2"
              vector-effect="non-scaling-stroke"
              filter="url(#ufGlow)"
            />

            <circle
              cx={elem(List.last(@uf_svg.data_points), 0)}
              cy={elem(List.last(@uf_svg.data_points), 1)}
              r="1.5"
              fill="#22d3ee"
            />
          </svg>

          <div
            class="absolute hidden pointer-events-none bg-black/90 text-white text-xs rounded-lg px-3 py-2 -top-12 left-1/2 -translate-x-1/2 z-50 shadow-xl border border-white/20"
            id="uf-tooltip"
          >
            <div class="font-semibold" id="uf-tooltip-value"></div>
            <div class="text-white/60 text-[10px]" id="uf-tooltip-date"></div>
          </div>

          <div class="flex justify-between mt-2 text-xs text-white/50 px-1">
            <span>{@uf_svg.first_date}</span>
            <span class="text-sky-400">Min: ${format_number(@uf_svg.min_val)}</span>
            <span class="text-sky-400">Max: ${format_number(@uf_svg.max_val)}</span>
            <span>{@uf_svg.last_date}</span>
          </div>
        </div>
      <% else %>
        <div class="h-24 flex items-center justify-center text-white/30">
          <div class="text-center">
            <.icon name="hero-chart-line-up" class="w-12 h-12 mx-auto mb-2 opacity-50" />
            <p class="text-sm">Sin historial UF disponible.</p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :refreshing, :boolean, required: true

  defp refresh_button(assigns) do
    ~H"""
    <div class="flex justify-center">
      <button
        phx-click="refresh"
        disabled={@refreshing}
        class="px-8 py-4 bg-sky-600 hover:bg-sky-500 disabled:bg-sky-600/50 text-white font-semibold rounded-xl transition-all flex items-center gap-3 shadow-lg shadow-blue-500/25"
      >
        <.icon name="hero-arrow-path" class={"w-5 h-5 #{if @refreshing, do: "animate-spin"}"} />
        <span>{if @refreshing, do: "Actualizando...", else: "Actualizar Datos"}</span>
      </button>
    </div>
    """
  end

  defp color_class("blue"), do: "bg-gradient-to-br from-blue-600 to-blue-700"
  defp color_class("green"), do: "bg-gradient-to-br from-emerald-600 to-emerald-700"
  defp color_class("purple"), do: "bg-gradient-to-br from-violet-600 to-violet-700"
  defp color_class("amber"), do: "bg-gradient-to-br from-amber-600 to-amber-700"
  defp color_class("rose"), do: "bg-gradient-to-br from-rose-600 to-rose-700"

  defp icon_bg_class("blue"), do: "bg-sky-500/20"
  defp icon_bg_class("green"), do: "bg-emerald-500/20"
  defp icon_bg_class("purple"), do: "bg-violet-500/20"
  defp icon_bg_class("amber"), do: "bg-amber-500/20"
  defp icon_bg_class("rose"), do: "bg-rose-500/20"

  defp icon_text_class("blue"), do: "text-sky-300"
  defp icon_text_class("green"), do: "text-emerald-300"
  defp icon_text_class("purple"), do: "text-violet-300"
  defp icon_text_class("amber"), do: "text-amber-300"
  defp icon_text_class("rose"), do: "text-rose-300"

  defp text_secondary_class("blue"), do: "text-sky-200"
  defp text_secondary_class("green"), do: "text-emerald-200"
  defp text_secondary_class("purple"), do: "text-violet-200"
  defp text_secondary_class("amber"), do: "text-amber-200"
  defp text_secondary_class("rose"), do: "text-rose-200"

  defp format_number(decimal) when is_struct(decimal, Decimal) do
    decimal
    |> Decimal.round(0)
    |> Decimal.to_integer()
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1.")
    |> String.reverse()
  end

  defp format_number(nil), do: "-"

  defp format_number(_), do: "0"

  defp format_full(decimal) when is_struct(decimal, Decimal) do
    decimal
    |> Decimal.round(0)
    |> Decimal.to_integer()
    |> format_with_dots()
  end

  defp format_with_dots(integer) when is_integer(integer) do
    integer
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1.")
    |> String.reverse()
  end

  defp format_full_abs(decimal) when is_struct(decimal, Decimal) do
    decimal |> Decimal.abs() |> format_full()
  end

  defp calculate_health_score(bank) do
    result = bank_resultado(bank)
    income = bank_ingresos(bank)
    activos = bank_activos(bank)

    cond do
      result == nil or income == nil or activos == nil ->
        nil

      true ->
        roa = Decimal.div(result, activos) |> Decimal.to_float()

        eficiencia =
          Decimal.div(Decimal.abs(bank_gastos(bank) || Decimal.new(0)), income)
          |> Decimal.to_float()

        roa_score =
          cond do
            roa >= 0.01 -> 40
            roa >= 0.005 -> 30
            roa >= 0.001 -> 20
            true -> 10
          end

        efic_score =
          cond do
            eficiencia <= 0.3 -> 30
            eficiencia <= 0.5 -> 20
            eficiencia <= 0.7 -> 10
            true -> 5
          end

        size_score =
          cond do
            Decimal.compare(activos, Decimal.new(50_000_000_000_000)) == :gt -> 20
            Decimal.compare(activos, Decimal.new(10_000_000_000_000)) == :gt -> 15
            Decimal.compare(activos, Decimal.new(1_000_000_000_000)) == :gt -> 10
            true -> 5
          end

        roa_score + efic_score + size_score
    end
  end

  defp calculate_health_label(score) do
    cond do
      score >= 80 -> "Excelente"
      score >= 60 -> "Bueno"
      score >= 40 -> "Regular"
      true -> "Bajo"
    end
  end

  defp health_score_color(score) do
    cond do
      score >= 80 -> "text-emerald-400"
      score >= 60 -> "text-sky-400"
      score >= 40 -> "text-yellow-400"
      true -> "text-sky-400"
    end
  end

  defp bank_resultado(bank) do
    if bank[:resultados], do: bank.resultados.resultado, else: nil
  end

  defp bank_ingresos(bank) do
    if bank[:resultados], do: bank.resultados.ingresos, else: nil
  end

  defp bank_gastos(bank) do
    if bank[:resultados], do: bank.resultados.gastos, else: nil
  end

  defp bank_activos(bank) do
    if bank[:balance], do: bank.balance.activos, else: nil
  end

  defp bank_pasivos(bank) do
    if bank[:balance], do: bank.balance.pasivos, else: nil
  end

  defp margen_neto(bank) do
    resultado = bank_resultado(bank)
    ingresos = bank_ingresos(bank)

    if resultado && ingresos && Decimal.compare(ingresos, Decimal.new(0)) != :eq do
      Decimal.div(resultado, ingresos)
      |> Decimal.mult(100)
      |> Decimal.round(1)
    else
      nil
    end
  end

  defp solvencia(bank) do
    activos = bank_activos(bank)
    pasivos = bank_pasivos(bank)

    if activos && pasivos && Decimal.compare(pasivos, Decimal.new(0)) != :eq do
      Decimal.div(activos, pasivos)
      |> Decimal.round(2)
    else
      nil
    end
  end

  defp sort_banks_by_score(banks) do
    Enum.sort_by(
      banks,
      fn bank ->
        calculate_health_score(bank) || 0
      end,
      :desc
    )
  end

  defp format_bank_name(name) do
    name
    |> String.replace("BANCO ", "")
    |> String.replace("BANCO DE ", "")
    |> String.replace("DE ", "")
  end

  defp format_month_year(year, month) do
    month_names = %{
      1 => "Enero",
      2 => "Febrero",
      3 => "Marzo",
      4 => "Abril",
      5 => "Mayo",
      6 => "Junio",
      7 => "Julio",
      8 => "Agosto",
      9 => "Septiembre",
      10 => "Octubre",
      11 => "Noviembre",
      12 => "Diciembre"
    }

    "#{month_names[month]} #{year}"
  end

  defp format_date(date) when is_struct(date, Date), do: Calendar.strftime(date, "%d/%m/%Y")
  defp format_date(_), do: "-"

  defp format_date_short(date) when is_struct(date, Date), do: Calendar.strftime(date, "%d %b %Y")
  defp format_date_short(_), do: "-"

  defp format_date_today, do: Calendar.strftime(Date.utc_today(), "%d/%m/%Y")

  defp calculate_ratio(uf, dolar) when is_struct(uf, Decimal) and is_struct(dolar, Decimal) do
    if Decimal.compare(dolar, Decimal.new(0)) == :gt do
      Decimal.div(uf, dolar) |> Decimal.round(2) |> Decimal.to_string()
    else
      "-"
    end
  end

  defp calculate_ratio(_, _), do: "-"

  defp load_indicators do
    case CmfClient.obtener_indicadores_completos() do
      {:ok, data} ->
        {data, nil}

      {:error, reason} ->
        {empty_indicator_payload(),
         format_data_error(reason, "No fue posible cargar indicadores CMF.")}
    end
  end

  defp load_uf_history do
    case CmfClient.obtener_historial_uf(1) do
      {:ok, history} -> {history, nil}
      {:error, reason} -> {[], format_data_error(reason, "No fue posible cargar historial UF.")}
    end
  end

  defp empty_indicator_payload do
    empty = %{valor: nil, fecha: nil}
    %{uf: empty, dolar: empty, euro: empty, utm: empty, ipc: empty}
  end

  defp format_data_error(reason, fallback) do
    case reason do
      {:http_status, status} -> "#{fallback} API respondió con estado #{status}."
      status when is_binary(status) -> "#{fallback} #{status}"
      _ -> fallback
    end
  end

  defp encode_uf_data(data_points) when is_list(data_points) do
    data_points
    |> Enum.map(fn {x, y, _valor, _fecha} -> %{x: x, y: y} end)
    |> JSON.encode!()
  end

  defp encode_uf_data(_), do: "[]"

  defp encode_uf_dates(data_dates) when is_list(data_dates) do
    data_dates
    |> Enum.map(&to_string/1)
    |> JSON.encode!()
  end

  defp encode_uf_dates(_), do: "[]"

  defp encode_uf_values(data_values) when is_list(data_values) do
    JSON.encode!(data_values)
  end

  defp encode_uf_values(_), do: "[]"
end
