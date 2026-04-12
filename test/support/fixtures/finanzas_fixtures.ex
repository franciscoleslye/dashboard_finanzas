defmodule DashboardFinanzas.FinanzasFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `DashboardFinanzas.Finanzas` context.
  """

  @doc """
  Generate a indicador.
  """
  def indicador_fixture(attrs \\ %{}) do
    {:ok, indicador} =
      attrs
      |> Enum.into(%{
        fecha: ~D[2026-04-07],
        nombre: "some nombre",
        valor: "120.5"
      })
      |> DashboardFinanzas.Finanzas.create_indicador()

    indicador
  end
end
