# How to save and restore rows from an arbitrary table
# A more complex example is here: https://gist.github.com/JoshCheek/e91fa717c14a16c04e9befb0cf5fe921
require_relative 'helpers'

# Schema
  sql <<~SQL
    -- This provides a hash-table type, keys and values are strings, it ships with postgresql
    create extension hstore;

    -- VERSION CONTROLLED ROWS
    -- Can store rows from any arbitrary table. I've tested this with tables that
    -- hold booleans, numbers, strings, composite types, enums, ranges, and hstores!
    create table vc_rows (
      id         serial primary key,
      col_values hstore
    );

    -- A TABLE WE WANT TO STORE IN VC
    create table users (
      id   serial primary key,
      name varchar
    );
  SQL

# Create some users
  original = sql <<~SQL
    insert into users (name)
    values ('Josh'), ('Ashton')
    returning *;
  SQL
  # => [#<Record id='1' name='Josh'>, #<Record id='2' name='Ashton'>]


# Save the users to version control
  sql <<~SQL
    insert into vc_rows (col_values)
    select hstore(users)
    from users
    returning *;
  SQL
  # => [#<Record id='1' col_values='"id"=>"1", "name"=>"Josh"'>,
  #     #<Record id='2' col_values='"id"=>"2", "name"=>"Ashton"'>]


# Delete the users
  sql 'delete from users;'
  sql 'select * from users;'
  # => []

# Restore the users from version control
  restored = sql <<~SQL
    insert into users
    select (populate_record(null::users, col_values)).*
    from vc_rows;

    select * from users;
  SQL

# They match!
  eq! original, restored
  # => [#<Record id='1' name='Josh'>, #<Record id='2' name='Ashton'>]
