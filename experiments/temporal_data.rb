require 'pg'
# PG.connect(dbname: 'postgres').exec('drop database josh_testing')
# PG.connect(dbname: 'postgres').exec('create database josh_testing')

db = PG.connect(dbname: 'josh_testing')
db.exec 'begin' # throws away changes when process exits

def db.exec(*)
  super.to_a
rescue Exception
  $!.set_backtrace caller.drop(1)
  raise
end


# model
db.exec <<~SQL
  create schema history;

  -- functions to manage the active_time, the time we are viewing the DB from
  create function history.set_active_time(text) returns text as $$
    begin
      perform set_config('history.active_time', $1, false);
      return $1;
    end $$ language plpgsql;

  create function history.get_active_time() returns timestamp as $$
    select coalesce(
      current_setting('history.active_time', true)::timestamp,
      now()
    )::timestamp
    $$ language sql;
  SQL

# Defaults to now, or the specified time
db.exec "select history.get_active_time()"                   # => [{"get_active_time"=>"2017-12-26 14:03:27.490336"}]
db.exec "select history.set_active_time('2010-01-01 14:30')" # => [{"set_active_time"=>"2010-01-01 14:30"}]
db.exec "select history.get_active_time()"                   # => [{"get_active_time"=>"2010-01-01 14:30:00"}]

db.exec <<~SQL
  -- load the gen_random_uuid function
  create extension pgcrypto;

  -- history table
  create table history.categories (
    uuid uuid primary key default gen_random_uuid(),
    id serial,
    active_time tsrange default tsrange('now', NULL), -- NOTE: tstzrange has zone
    name text,
    is_preferred boolean
  );
  SQL


# Insert some rows
categories = db.exec <<~SQL
  insert into history.categories (name, is_preferred, active_time)
    values ('office supplies', false, '[2010-01-01 14:30, 2010-01-01 15:30)'),
           ('tools',           false, '[2010-01-01 13:30, 2010-01-01 14:45)')
  SQL

# View to query the historical category data
db.exec <<~SQL
  create view public.categories as
    select *
    from history.categories c
    where c.active_time @> history.get_active_time();
  SQL

# Depending on the active time, we get back different results
db.exec "select history.set_active_time('2010-01-01 13:29')"
db.exec 'select name from categories' # => []

db.exec "select history.set_active_time('2010-01-01 13:30')"
db.exec 'select name from categories' # => [{"name"=>"tools"}]

db.exec "select history.set_active_time('2010-01-01 14:30')"
db.exec 'select name from categories' # => [{"name"=>"office supplies"}, {"name"=>"tools"}]

db.exec "select history.set_active_time('2010-01-01 14:45')"
db.exec 'select name from categories' # => [{"name"=>"office supplies"}]

db.exec "select history.set_active_time('2010-01-01 15:30')"
db.exec 'select name from categories' # => []
