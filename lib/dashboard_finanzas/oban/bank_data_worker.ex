defmodule DashboardFinanzas.BankDataWorker do
  use Oban.Worker, queue: :bank_data

  alias DashboardFinanzas.{BankData, BankDataServer}

  @impl true
  def perform(%Oban.Job{args: %{"task" => "fetch_all"}}) do
    {year, month} = get_period()

    case BankData.obtener_bancos(year, month) do
      {:ok, banks_list} ->
        banks_data =
          Enum.map(banks_list, fn bank ->
            Process.sleep(100)

            balance =
              fetch_data_with_retry(fn ->
                BankData.obtener_balance_resumen(year, month, bank.code)
              end)

            resultado =
              fetch_data_with_retry(fn ->
                BankData.obtener_estado_resultados(year, month, bank.code)
              end)

            %{
              code: bank.code,
              name: bank.name,
              balance: balance,
              resultados: resultado
            }
          end)

        Cachex.put(:bank_cache, "all_banks", banks_data, ttl: :timer.hours(6))
        BankDataServer.refresh()

        {:ok, "Fetched #{length(banks_data)} banks"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def perform(%Oban.Job{args: %{"task" => "fetch_single", "code" => code}}) do
    {year, month} = get_period()

    balance = BankData.obtener_balance_resumen(year, month, code)
    resultado = BankData.obtener_estado_resultados(year, month, code)

    {:ok, %{balance: balance, resultados: resultado}}
  end

  @impl true
  def perform(%Oban.Job{args: %{"task" => "periodic_fetch"}}) do
    fetch_and_cache()
    :ok
  end

  defp fetch_and_cache do
    {year, month} = get_period()

    with {:ok, banks_list} <- BankData.obtener_bancos(year, month) do
      banks_data =
        Enum.map(banks_list, fn bank ->
          Process.sleep(100)

          balance =
            fetch_data_with_retry(fn ->
              BankData.obtener_balance_resumen(year, month, bank.code)
            end)

          resultado =
            fetch_data_with_retry(fn ->
              BankData.obtener_estado_resultados(year, month, bank.code)
            end)

          %{
            code: bank.code,
            name: bank.name,
            balance: balance,
            resultados: resultado
          }
        end)

      Cachex.put(:bank_cache, "all_banks", banks_data, ttl: :timer.hours(6))
    end
  end

  defp fetch_data_with_retry(fun, retries \\ 3) do
    Enum.reduce_while(1..retries, nil, fn _attempt, _acc ->
      case fun.() do
        {:ok, data} -> {:halt, data}
        {:error, _} -> {:cont, nil}
      end
    end)
  end

  defp get_period do
    today = Date.utc_today()

    if today.month == 1 do
      {today.year - 1, 12}
    else
      {today.year, today.month - 1}
    end
  end
end
