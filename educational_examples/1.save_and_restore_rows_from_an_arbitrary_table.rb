# How to save and restore rows from an arbitrary table
# A more complex example is here: https://gist.github.com/JoshCheek/e91fa717c14a16c04e9befb0cf5fe921
require_relative 'helpers'

# Schema
sql <<~SQL
  -- This provides a hash-table type, keys and values are strings, it ships with postgresql
  create extension hstore;

  -- A BACKUP TABLE
  -- Can store rows from arbitrary other tables. To generalize, store the name of
  -- which table it's backing up. I've tested this with tables that hold booleans,
  -- numbers, strings, composite types, enums, and hstores
  create table backup (
    id         serial primary key,
    col_values hstore
  );

  -- A TABLE WE WANT TO BACK UP
  create table users (
    id   serial primary key,
    name varchar
  );
  SQL

# Create some users
original = sql <<~SQL
  insert into users (name)
  values ('Josh'), ('Sally')
  returning *;
  SQL
  # => [#<Record id="1" name="Josh">, #<Record id="2" name="Sally">]


# Back the users up
sql <<~SQL
  insert into backup (col_values)
  select hstore(users)
  from users
  returning *;
  SQL
  # => [#<Record id="1" col_values="\"id\"=>\"1\", \"name\"=>\"Josh\"">,
  #     #<Record id="2" col_values="\"id\"=>\"2\", \"name\"=>\"Sally\"">]


# Delete the users
sql 'delete from users;'
sql 'select * from users;'
  # => []

# Restore them from the backup
restored = sql <<~SQL
  insert into users
  select (populate_record(null::users, col_values)).*
  from backup;

  select * from users;
  SQL

# They match!
assert_equal original, restored
  # => [#<Record id="1" name="Josh">, #<Record id="2" name="Sally">]
