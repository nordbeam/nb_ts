defmodule NbTs.TsgoValidatorTest do
  use ExUnit.Case, async: true

  alias NbTs.TsgoValidator

  describe "validate/1" do
    test "validates simple TypeScript" do
      assert {:ok, _} = TsgoValidator.validate("const x: number = 5")
    end

    test "rejects type errors" do
      assert {:error, _} = TsgoValidator.validate("const x: number = 'bad'")
    end
  end
end
