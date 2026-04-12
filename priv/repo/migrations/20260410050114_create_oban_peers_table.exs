defmodule DashboardFinanzas.Repo.Migrations.CreateObanPeersTable do
  use Ecto.Migration

  def change do
    create table(:oban_peers) do
      add :node, :string, null: false
      add :lock, :string, null: true

      timestamps(type: :utc_datetime_usec, null: true)
    end

    create index(:oban_peers, [:node], unique: true)
    create index(:oban_peers, [:lock])
  end
end
