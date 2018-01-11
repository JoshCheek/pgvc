defmodule JoshTest.Repo.Migrations.Init do
  use Ecto.Migration

  def up do
    execute "
      create schema omghi;
    "

    execute "
      create table omghi.wat (
        bbq serial primary key,
        lol text
      );
    "
  end
end
