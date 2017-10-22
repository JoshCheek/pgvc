require 'pg'
# PG.connect(dbname: 'postgres').exec('drop database josh_testing')
# PG.connect(dbname: 'postgres').exec('create database josh_testing')
db = PG.connect(dbname: 'josh_testing')
db.exec 'begin' # throws away changes when process exits

def db.exec(*)
  super.to_a
end

db.exec <<~SQL
  create function deref(integer) returns varchar as $$
    select $1::text||'int'
  $$ language sql;

  create function deref(varchar) returns varchar as $$
    select $1||'varchar'
  $$ language sql;

  create function deref(text) returns varchar as $$
    select $1::varchar||'text'
  $$ language sql;

  select deref(1) as a,
         deref('1') as b,
         deref('1'::varchar) as c;
  SQL
  # => [{"a"=>"1int", "b"=>"1text", "c"=>"1varchar"}]
