require 'pg'

# Reset the database
db = lambda do |name|
  PG.connect(dbname: 'postgres')
    .tap { |db| db.exec "drop database if exists #{name};" }
    .tap { |db| db.exec "create database #{name};" }
  PG.connect(dbname: name).tap do |db|
    # Make the db a little nicer to work with for our experiment
    def db.exec(*)
      super.map { |row| row.map { |k, v| [k.intern, v] }.to_h }
    rescue PG::Error
      $!.set_backtrace caller.drop(1)
      raise
    end
  end
end.call('josh_testing')


# The values being stored (going to use their id as the value)
db.exec <<~SQL
  create extension hstore;
  create table backup (
    id         serial primary key,
    col_values hstore
  );

  -- test it against a table with some sophisticated types
  create type user_type as enum ('admin', 'moderator', 'user');
  create type login_device as (name varchar, loggedin_at timestamp);
  create table users (
    id          serial primary key, -- an autoincrementing value
    name        varchar,            -- string
    type        user_type,          -- enum
    is_active   bool,               -- boolean
    preferences hstore,             -- hstore (this will be nested)
    device      login_device        -- composite type
  );
  SQL

# create some users (but should work for an arbitrary table)
original = db.exec <<~SQL
  insert into users (name, type, is_active, preferences, device)
  values ('Josh', 'admin', true, 'a=>b,c=>d', ('macbook', now())),
         ('Sally', 'moderator', false, '', null)
  returning *;
  SQL
  # => [{:id=>"1",
  #      :name=>"Josh",
  #      :type=>"admin",
  #      :is_active=>"t",
  #      :preferences=>"\"a\"=>\"b\", \"c\"=>\"d\"",
  #      :device=>"(macbook,\"2017-10-16 23:47:14.543174\")"},
  #     {:id=>"2",
  #      :name=>"Sally",
  #      :type=>"moderator",
  #      :is_active=>"f",
  #      :preferences=>"",
  #      :device=>nil}]


# back the users up
db.exec <<~SQL
  insert into backup (col_values)
  select hstore(users)
  from users
  returning *;
  SQL
  # => [{:id=>"1",
  #      :col_values=>
  #       "\"id\"=>\"1\", \"name\"=>\"Josh\", \"type\"=>\"admin\", \"device\"=>\"(macbook,\\\"2017-10-16 23:47:14.543174\\\")\", \"is_active\"=>\"t\", \"preferences\"=>\"\\\"a\\\"=>\\\"b\\\", \\\"c\\\"=>\\\"d\\\"\""},
  #     {:id=>"2",
  #      :col_values=>
  #       "\"id\"=>\"2\", \"name\"=>\"Sally\", \"type\"=>\"moderator\", \"device\"=>NULL, \"is_active\"=>\"f\", \"preferences\"=>\"\""}]


# delete the users
db.exec <<~SQL
  delete from users;
  select * from users;
  SQL
  # => []


# restore them from the backup
backed_up = db.exec <<~SQL
  insert into users
  select (populate_record(null::users, col_values)).*
  from backup;

  select * from users;
  SQL
  # => [{:id=>"1",
  #      :name=>"Josh",
  #      :type=>"admin",
  #      :is_active=>"t",
  #      :preferences=>"\"a\"=>\"b\", \"c\"=>\"d\"",
  #      :device=>"(macbook,\"2017-10-16 23:47:14.543174\")"},
  #     {:id=>"2",
  #      :name=>"Sally",
  #      :type=>"moderator",
  #      :is_active=>"f",
  #      :preferences=>"",
  #      :device=>nil}]

# do they match?
original == backed_up # => true

# next id should be 3
db.exec <<~SQL
  insert into users (name, type, is_active, preferences, device)
  values ('Carla', 'user', true, '', null)
  returning *;
  SQL
  # => [{:id=>"3",
  #      :name=>"Carla",
  #      :type=>"user",
  #      :is_active=>"t",
  #      :preferences=>"",
  #      :device=>nil}]
