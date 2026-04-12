defmodule DashboardFinanzas.BankDataScheduler do
  use GenServer
  alias DashboardFinanzas.BankDataWorker

  @interval :timer.hours(6)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_job()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:schedule, state) do
    :ok = Oban.insert(%Oban.Job{
      worker: BankDataWorker,
      args: %{"task" => "periodic_fetch"},
      queue: :bank_data,
      scheduled_at: DateTime.add(DateTime.utc_now(), 60 * 5)
    })

    schedule_job()
    {:noreply, state}
  end

  defp schedule_job do
    Process.send_after(self(), :schedule, @interval)
  end
end
