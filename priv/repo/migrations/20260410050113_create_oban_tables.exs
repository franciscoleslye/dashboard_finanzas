defmodule DashboardFinanzas.Repo.Migrations.CreateObanTables do
  use Ecto.Migration

  def change do
    create table(:oban_jobs) do
      add :state, :string, null: false, default: "available"
      add :queue, :string, null: false, default: "default"
      add :worker, :string, null: false
      add :args, :map, null: false, default: %{}
      add :meta, :map, null: false, default: %{}
      add :tags, {:array, :string}, null: false, default: []
      add :errors, {:array, :map}, null: false, default: []
      add :attempt, :integer, null: false, default: 0
      add :attempted_at, :utc_datetime_usec, null: true
      add :attempted_by, {:array, :string}, null: true
      add :max_attempts, :integer, null: false, default: 20
      add :priority, :integer, null: false, default: 0
      add :cancelled_at, :utc_datetime_usec, null: true
      add :completed_at, :utc_datetime_usec, null: true
      add :discarded_at, :utc_datetime_usec, null: true
      add :scheduled_at, :utc_datetime_usec, null: false, default: fragment("NOW()")

      timestamps(type: :utc_datetime_usec, null: true)
    end

    create index(:oban_jobs, [:queue, :state])
    create index(:oban_jobs, [:scheduled_at])
    create index(:oban_jobs, [:worker])
    create index(:oban_jobs, [:tags])
    create index(:oban_jobs, [:cancelled_at])
    create index(:oban_jobs, [:completed_at])
    create index(:oban_jobs, [:discarded_at])
  end
end
