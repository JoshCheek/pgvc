require 'pg'
# PG.connect(dbname: 'postgres').exec('drop database josh_testing')
# PG.connect(dbname: 'postgres').exec('create database josh_testing')
db = PG.connect(dbname: 'josh_testing')
db.exec 'begin' # throws away changes when process exits

def db.exec(*)
  super.to_a
end

db.exec <<~SQL
  create function fn(integer) returns varchar as $$
    select $1::text||':integer'
  $$ language sql;

  create function fn(varchar) returns varchar as $$
    select $1||':varchar'
  $$ language sql;

  create function fn(text) returns varchar as $$
    select $1::varchar||':text'
  $$ language sql;

  select fn(1)            as one,
         fn('2')          as two,
         fn('3'::varchar) as three;
  SQL
  # => [{"one"=>"1:integer", "two"=>"2:text", "three"=>"3:varchar"}]
