defmodule DashboardFinanzas.FinanzasTest do
  use DashboardFinanzas.DataCase

  alias DashboardFinanzas.Finanzas

  describe "indicadores" do
    alias DashboardFinanzas.Finanzas.Indicador

    import DashboardFinanzas.FinanzasFixtures

    @invalid_attrs %{nombre: nil, valor: nil, fecha: nil}

    test "list_indicadores/0 returns all indicadores" do
      indicador = indicador_fixture()
      assert Finanzas.list_indicadores() == [indicador]
    end

    test "get_indicador!/1 returns the indicador with given id" do
      indicador = indicador_fixture()
      assert Finanzas.get_indicador!(indicador.id) == indicador
    end

    test "create_indicador/1 with valid data creates a indicador" do
      valid_attrs = %{nombre: "some nombre", valor: "120.5", fecha: ~D[2026-04-07]}

      assert {:ok, %Indicador{} = indicador} = Finanzas.create_indicador(valid_attrs)
      assert indicador.nombre == "some nombre"
      assert indicador.valor == Decimal.new("120.5")
      assert indicador.fecha == ~D[2026-04-07]
    end

    test "create_indicador/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Finanzas.create_indicador(@invalid_attrs)
    end

    test "update_indicador/2 with valid data updates the indicador" do
      indicador = indicador_fixture()
      update_attrs = %{nombre: "some updated nombre", valor: "456.7", fecha: ~D[2026-04-08]}

      assert {:ok, %Indicador{} = indicador} = Finanzas.update_indicador(indicador, update_attrs)
      assert indicador.nombre == "some updated nombre"
      assert indicador.valor == Decimal.new("456.7")
      assert indicador.fecha == ~D[2026-04-08]
    end

    test "update_indicador/2 with invalid data returns error changeset" do
      indicador = indicador_fixture()
      assert {:error, %Ecto.Changeset{}} = Finanzas.update_indicador(indicador, @invalid_attrs)
      assert indicador == Finanzas.get_indicador!(indicador.id)
    end

    test "delete_indicador/1 deletes the indicador" do
      indicador = indicador_fixture()
      assert {:ok, %Indicador{}} = Finanzas.delete_indicador(indicador)
      assert_raise Ecto.NoResultsError, fn -> Finanzas.get_indicador!(indicador.id) end
    end

    test "change_indicador/1 returns a indicador changeset" do
      indicador = indicador_fixture()
      assert %Ecto.Changeset{} = Finanzas.change_indicador(indicador)
    end
  end
end
