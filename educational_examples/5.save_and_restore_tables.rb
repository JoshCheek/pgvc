# Save and restore tables
require_relative 'helpers'

sql <<~SQL
  create extension hstore;

  create table vc_tables (
    vc_hash    character(32),
    row_hashes character(32)[]
  );

  create table vc_rows (
    vc_hash character(32),
    tbl     varchar,
    data    hstore
  );


  -- Record changes to users
  create table users (
    id      serial primary key,
    name    varchar,
    vc_hash character(32)
  );


  -- triggers to calculate the hash and store the record in version control
  create or replace function vc_hash_and_record()
  returns trigger as $$
  declare
    serialized hstore;
  begin
    NEW.vc_hash = null;
    select hstore(NEW) into serialized;
    select delete(serialized, 'vc_hash') into serialized;
    NEW.vc_hash = md5(serialized::text);
    insert into vc_rows (vc_hash, tbl, data)
      select NEW.vc_hash, TG_TABLE_NAME, serialized
      where not exists (select vc_hash from vc_rows where vc_hash = NEW.vc_hash);
    return NEW;
  end $$ language plpgsql;


  create trigger vc_hash_and_record_tg
    before insert or update on users
    for each row execute procedure vc_hash_and_record();


  create function commit_table(in table_name varchar)
  returns character(32) as $$
  declare
    row_hashes character(32)[];
    table_hash character(32);
  begin
    execute
      format('select array_agg(vc_hash) from users;', quote_ident(table_name))
      into row_hashes;
    select md5(row_hashes::text)
      into table_hash;
    insert into vc_tables (vc_hash, row_hashes)
      values (table_hash, row_hashes);
    return table_hash;
  end
  $$ language plpgsql;


  create function checkout_table(in table_hash character(32))
  returns void as $$
  declare
    hashes character(32)[];
  begin
    select row_hashes from vc_tables where vc_hash = table_hash into hashes;
    delete from users;
    insert into users
      select (populate_record(null::users, data)).*
      from unnest(hashes) recorded_hash
      left join vc_rows on vc_hash = recorded_hash;
  end
  $$ language plpgsql
SQL


def commit_users
  sql("select commit_table('users') as vc_hash").first.vc_hash
end

empty = commit_users
sql "insert into users (name) values ('Yumin'), ('Gomez')"
yg = commit_users
sql "insert into users (name) values ('Anca')"
yga = commit_users
sql "delete from users where name = 'Gomez'"
ya = commit_users
sql "update users set name = 'Yooms' where name = 'Yumin'"
y2a = commit_users


def checkout(table_hash)
  sql "select checkout_table($1)", table_hash
  sql("select name from users order by id").map(&:name)
end

eq! %w[],                 checkout(empty)
eq! %w[Yumin Gomez],      checkout(yg)
eq! %w[Yumin Gomez Anca], checkout(yga)
eq! %w[Yumin Anca],       checkout(ya)
eq! %w[Yooms Anca],       checkout(y2a)
