defmodule DashboardFinanzas.Repo do
  use Ecto.Repo,
    otp_app: :dashboard_finanzas,
    adapter: Ecto.Adapters.Postgres
end
