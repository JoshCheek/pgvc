require 'pg'
# PG.connect(dbname: 'postgres').exec('drop database josh_testing')
# PG.connect(dbname: 'postgres').exec('create database josh_testing')
db = PG.connect(dbname: 'josh_testing')
db.exec 'begin' # throws away changes when process exits
def db.exec(*)
  super.to_a
end

db.exec <<~SQL
  create function multi(out b varchar, out c varchar) as $$
    begin
      b := 'bee';
      c := 'see';
    end $$ language plpgsql;


  create function using_record() returns varchar as $$
    declare
      r record;
      d varchar;
      e varchar;
    begin
      r := multi();
      d := r.b;
      e := r.c;
      return d||' '||e;
    end $$ language plpgsql;


  -- Sheesh, I figured this must exist, but it took forever to figure itout!
  create or replace function using_select_into() returns varchar as $$
    declare
      d varchar;
      e varchar;
    begin
      select b, c into d, e from multi();
      return d||' '||e;
    end $$ language plpgsql;


  select using_record(), using_select_into();
  SQL
  # => [{"using_record"=>"bee see", "using_select_into"=>"bee see"}]


