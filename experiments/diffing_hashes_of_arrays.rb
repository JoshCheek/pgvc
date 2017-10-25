require 'pg'
# PG.connect(dbname: 'postgres').exec('drop database josh_testing')
# PG.connect(dbname: 'postgres').exec('create database josh_testing')
db = PG.connect(dbname: 'josh_testing')
db.exec 'begin' # throws away changes when process exits

def db.exec(*)
  super.to_a
end

db.exec <<~SQL
  create extension hstore;

  create table tables (
    vc_hash      text primary key,
    table_hashes hstore
  );
  insert into tables (vc_hash, table_hashes)
    values ('abc', '"comments"=>"{first}", "users"=>"{erin}",       "products"=>"{boots,cleats}"'),
           ('def', '"comments"=>"{first}", "users"=>"{erin,clark}", "products"=>"{shoes,cleats}"');


  create function whatever() returns table(table_name text, action text, val text) as $$
    declare
      hl hstore := (select table_hashes from tables where vc_hash = 'abc');
      hr hstore := (select table_hashes from tables where vc_hash = 'def');
      mismatched_keys text[] := akeys(hl-hr);
      key text;
    begin
      foreach key in array
        mismatched_keys
      loop
        return query with
          lhs as (select unnest((hl->key)::text[]) as val),
          rhs as (select unnest((hr->key)::text[]) as val),
          lhs_only as (select lhs.val from lhs left  join rhs on (lhs = rhs) where rhs is null),
          rhs_only as (select rhs.val from lhs right join rhs on (lhs = rhs) where lhs is null)
          select key, 'delete', * from lhs_only
          union all
          select key, 'insert', * from rhs_only;
      end loop;
    end $$ language plpgsql;

  select * from whatever();
  SQL
  # => [{"table_name"=>"users", "action"=>"insert", "val"=>"clark"},
  #     {"table_name"=>"products", "action"=>"delete", "val"=>"boots"},
  #     {"table_name"=>"products", "action"=>"insert", "val"=>"shoes"}]
