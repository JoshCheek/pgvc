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

  create table databases (
    vc_hash      varchar primary key,
    table_hashes hstore
  );

  insert into databases (vc_hash, table_hashes)
    values ('abc', 'a=>b,c=>d'::hstore),
           ('def', 'a=>b,c=>e'::hstore);

  create function whatever() returns void as $$
    declare
      h1 hstore := (select table_hashes from databases where vc_hash = 'abc');
      h2 hstore := (select table_hashes from databases where vc_hash = 'def');
      mismatched_keys varchar[] := akeys(h1-h2);
      key varchar;
    begin
      foreach key in array
        mismatched_keys
      loop
        raise warning 'Mismatched key: %', key;
        raise warning 'h1 val:         %', h1->key;
        raise warning 'h2 val:         %', h2->key;
      end loop;
    end $$ language plpgsql;

  select whatever();
  SQL

# !> WARNING:  Mismatched key: c
# !> WARNING:  h1 val:         d
# !> WARNING:  h2 val:         e
