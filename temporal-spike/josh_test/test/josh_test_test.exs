defmodule JoshTestTest do
  # This lets you place `IEx.pry` in the code, the same way you would use `binding.pry` in Ruby.
  # Note that to use that, you must run the tests with `iex -S mix test`
  require IEx

  use ExUnit.Case
  doctest JoshTest

  def get_db do
    dbconfig   = Application.get_env(:josh_test, JoshTest.Repo)
    {:ok, pid} = Postgrex.start_link database: dbconfig[:database]
    pid
  end

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

  test "can insert and query a user" do
    db = get_db()
    Postgrex.query! db, "begin", []
    Postgrex.query! db, "create table users (id serial primary key, name text)", []
    Postgrex.query! db, "insert into users (name) values ('josh')", []
    result = Postgrex.query! db, "select name from users", []
    assert first_row(result) == ["josh"]
    Postgrex.query! db, "rollback", []
  end
end
