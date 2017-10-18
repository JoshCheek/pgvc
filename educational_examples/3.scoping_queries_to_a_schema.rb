# Setting the default schema so that the same query will yield different results,
# depending on the context the user is in (hence, schemas will act as namespaces
# for branches)

require_relative 'helpers'

sql <<-SQL
  create schema first;
  create schema second;

  create table public.users (name varchar);
  create table first.users  (name varchar);
  create table second.users (name varchar);

  insert into public.users (name) VALUES ('josh');
  insert into first.users  (name) VALUES ('ashton');
  insert into second.users (name) VALUES ('yumin');
  SQL

# Three connections
name = $db.conninfo_hash[:dbname]
db1  = $db
db2  = PG::Connection.new dbname: name
db3  = PG::Connection.new dbname: name

# Each connection is associated a given schema
sql "set search_path = 'first'",  db: db2
sql "set search_path = 'second'", db: db3

# And, when executing the query, each finds its associated record
sql 'select * from users', db: db1 # => [#<Record name="josh">]
sql 'select * from users', db: db2 # => [#<Record name="ashton">]
sql 'select * from users', db: db3 # => [#<Record name="yumin">]
