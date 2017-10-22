DBNAME = 'pgvc_testing'
begin
  ROOT_DB = PG.connect dbname: DBNAME
rescue PG::ConnectionBad
  PG.connect(dbname: 'postgres').exec("create database #{DBNAME};")
  retry
end

ROOT_DB.exec <<~SQL
  SET client_min_messages=WARNING;

  create or replace function reset_test_db() returns void as $$
    declare
      name varchar;
    begin
      for name in
        select schema_name from information_schema.schemata
      loop
        if name like 'branch_%' then
          execute format('drop schema %s cascade', quote_ident(name));
        end if;
      end loop;
      drop schema if exists vc cascade;
      drop table if exists users;
      drop table if exists products;
    end $$ language plpgsql;
SQL

