# Save and restore tables
require_relative 'helpers'

sql <<~SQL
  create extension hstore;

  -- Version control
  create table vc_tables (
    vc_hash    character(32) primary key,
    row_hashes character(32)[]
  );
  create table vc_rows (
    vc_hash    character(32) primary key,
    col_values hstore
  );


  -- Record changes to users
  create table users (
    id      serial primary key,
    name    varchar,
    vc_hash character(32)
  );


  -- Calculate the hash and store the record in version control
  create function vc_hash_and_record() returns trigger as $$
    declare serialized hstore;
    begin
      serialized := delete(hstore(NEW), 'vc_hash');
      NEW.vc_hash = md5(serialized::text);
      insert into vc_rows (vc_hash, col_values)
        select NEW.vc_hash, serialized
        on conflict do nothing;
      return NEW;
    end $$ language plpgsql;

  -- Hash and store on every insert / update
  create trigger vc_hash_and_record_tg
    before insert or update on users
    for each row execute procedure vc_hash_and_record();

  -- Save the table
  create function commit_table(in table_name varchar, out table_hash character(32)) as $$
    declare row_hashes character(32)[];
    begin
      execute
        format('select array_agg(vc_hash) from %s;', quote_ident(table_name))
        into row_hashes;
      row_hashes := coalesce(row_hashes, '{}'); -- use empty array rather than null
      insert into vc_tables (vc_hash, row_hashes)
        values (md5(row_hashes::text), row_hashes)
        returning vc_hash into table_hash;
    end $$ language plpgsql;

  -- Restore a previously saved table
  create function checkout_table(in table_hash character(32)) returns void as $$
    declare hashes character(32)[];
    begin
      hashes := (select row_hashes from vc_tables where vc_hash = table_hash);
      delete from users;
      insert into users
        select vc_user.*
        from unnest(hashes) as hash
        join vc_rows on vc_hash = hash
        join populate_record(null::users, col_values) as vc_user on true;
    end $$ language plpgsql
SQL


def commit
  sql("select commit_table('users') as vc_hash").first.vc_hash
end
EMPTY = commit
sql "insert into users (name) values ('Yumin'), ('Gomez')"
YG    = commit
sql "insert into users (name) values ('Anca')"
YGA   = commit
sql "delete from users where name = 'Gomez'"
YA    = commit
sql "update users set name = 'Yooms' where name = 'Yumin'"
Y2A   = commit


def checkout(table_hash)
  sql "select checkout_table($1)", table_hash
  sql("select name from users order by id").map(&:name)
end
eq! %w[],                 checkout(EMPTY) # => []
eq! %w[Yumin Gomez],      checkout(YG)    # => ['Yumin', 'Gomez']
eq! %w[Yumin Gomez Anca], checkout(YGA)   # => ['Yumin', 'Gomez', 'Anca']
eq! %w[Yumin Anca],       checkout(YA)    # => ['Yumin', 'Anca']
eq! %w[Yooms Anca],       checkout(Y2A)   # => ['Yooms', 'Anca']
