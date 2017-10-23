# Setting the default schema so that the same query will yield different results,
# depending on the context the user is in (hence, schemas will act as namespaces
# for branches)
require_relative 'helpers'

sql <<~SQL
  create schema first;
  create schema second;
  create schema third;

  create table first.users  (name varchar);
  create table second.users (name varchar);
  create table third.users  (name varchar);

  insert into first.users  (name) VALUES ('Josh');
  insert into second.users (name) VALUES ('Ashton');
  insert into third.users  (name) VALUES ('Yumin');
SQL

# Three connections
db1 = PG::Connection.new dbname: dbname
db2 = PG::Connection.new dbname: dbname
db3 = PG::Connection.new dbname: dbname

# Each connection is associated a given schema
sql "set search_path = first",  db: db1
sql "set search_path = second", db: db2
sql "set search_path = third",  db: db3

# And, when executing the query, each finds its associated record
sql 'select * from users', db: db1 # => [#<Record name='Josh'>]
sql 'select * from users', db: db2 # => [#<Record name='Ashton'>]
sql 'select * from users', db: db3 # => [#<Record name='Yumin'>]
