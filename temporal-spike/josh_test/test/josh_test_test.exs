defmodule JoshTestTest do
  use ExUnit.Case
  doctest JoshTest

  def first_row(result) do
    # eg: %Postgrex.Result{
    #   columns:       ["count"],
    #   command:       :select,
    #   connection_id: 51557,
    #   num_rows:      1,
    #   rows:          [[1148870]]
    # }
    %Postgrex.Result{rows: [row]} = result
    row
  end

  test "greets the world" do
    {:ok, pid} = Postgrex.start_link database: "pgvc_testing"
    result = Postgrex.query! pid, "SELECT name FROM users", []
    assert first_row(result) == ["josh"]
  end
end
