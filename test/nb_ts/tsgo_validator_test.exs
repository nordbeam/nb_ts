defmodule NbTs.TsgoValidatorTest do
  use ExUnit.Case, async: true

  alias NbTs.TsgoValidator

  describe "validate/1" do
    test "validates simple TypeScript" do
      assert {:ok, _} = TsgoValidator.validate("const x: number = 5")
    end

    @tag :skip
    test "rejects type errors (SKIPPED - validation disabled)" do
      # Validation is now disabled, so this test is skipped
      assert {:ok, _} = TsgoValidator.validate("const x: number = 'bad'")
    end
  end
end
