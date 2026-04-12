defmodule DashboardFinanzas.Finanzas.Indicador do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "indicadores" do
    field :nombre, :string
    field :valor, :decimal
    field :fecha, :date

    timestamps()
  end

  def changeset(indicador, attrs) do
    indicador
    |> cast(attrs, [:nombre, :valor, :fecha])
    |> validate_required([:nombre, :valor, :fecha])
    |> unique_constraint([:nombre, :fecha])
  end
end