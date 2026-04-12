defmodule DashboardFinanzas.BankDataServer do
  use GenServer
  alias DashboardFinanzas.BankData

  @interval :timer.hours(6)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    state = %{
      banks: [],
      last_updated: nil,
      loading: false,
      period: {2025, 3}
    }

    schedule_fetch()
    {:ok, state}
  end

  @impl true
  def handle_info(:fetch, state) do
    new_state = fetch_all_banks(state)
    schedule_fetch()
    {:noreply, %{new_state | last_updated: DateTime.utc_now()}}
  end

  @impl true
  def handle_call(:get_banks, _from, state) do
    {:reply, state.banks, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:refresh, _from, state) do
    new_state = fetch_all_banks(state)
    {:reply, new_state.banks, %{new_state | last_updated: DateTime.utc_now()}}
  end

  defp fetch_all_banks(state) do
    {year, month} = state.period

    case BankData.obtener_bancos(year, month) do
      {:ok, banks_list} ->
        banks_data = Enum.map(banks_list, fn bank ->
          balance = fetch_with_retry(fn -> BankData.obtener_balance_resumen(year, month, bank.code) end)
          resultado = fetch_with_retry(fn -> BankData.obtener_estado_resultados(year, month, bank.code) end)

          %{
            code: bank.code,
            name: bank.name,
            balance: balance,
            resultados: resultado
          }
        end)

        Cachex.put(:bank_cache, "all_banks", banks_data, ttl: :timer.hours(6))
        %{state | banks: banks_data, loading: false}

      {:error, _} ->
        %{state | loading: false}
    end
  end

  defp fetch_with_retry(fun, retries \\ 3) do
    Enum.reduce_while(1..retries, nil, fn _attempt, _acc ->
      case fun.() do
        {:ok, data} -> {:halt, data}
        {:error, _} -> {:cont, nil}
      end
    end)
  end

  defp schedule_fetch do
    Process.send_after(self(), :fetch, @interval)
  end

  def get_banks do
    GenServer.call(__MODULE__, :get_banks)
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def refresh do
    GenServer.call(__MODULE__, :refresh)
  end
end
