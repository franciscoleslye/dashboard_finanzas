defmodule DashboardFinanzas.Repo.Migrations.CreateIndicadores do
  use Ecto.Migration

  def change do
    create table(:indicadores, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :nombre, :string, null: false      # "UF"
      add :valor, :decimal, precision: 12, scale: 2, null: false
      add :fecha, :date, null: false

      timestamps()
    end

    # Crucial: Evita tener dos veces la UF para el mismo día
    create unique_index(:indicadores, [:nombre, :fecha])
  end
end