# How to hash and backup every state of the record

require_relative 'helpers'

# Tables and Trigger
  sql <<~SQL
    -- version controlled rows
    create extension hstore;
    create table vc_rows (
      vc_hash character(32),
      tbl     varchar,
      data    hstore
    );

    -- record changes to this table
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
  SQL


# =====  INSERTION  =====
  # adds hashes them and saves them into the version controlled rows table
  users1 = sql <<~SQL
    insert into users (name)
    values ('Joshua'), ('Ashton')
    returning *;
  SQL
  # => [#<Record id="1"
  #              name="Joshua"
  #              vc_hash="c9d162308673136bc326be767b111fe9">,
  #     #<Record id="2"
  #              name="Ashton"
  #              vc_hash="ae3813fbddf04017880ec39a25fcc70e">]

  vc1 = sql 'select * from vc_rows'
  # => [#<Record vc_hash="c9d162308673136bc326be767b111fe9"
  #              tbl="users"
  #              data="\"id\"=>\"1\", \"name\"=>\"Joshua\"">,
  #     #<Record vc_hash="ae3813fbddf04017880ec39a25fcc70e"
  #              tbl="users"
  #              data="\"id\"=>\"2\", \"name\"=>\"Ashton\"">]

  eq! users1.map(&:vc_hash), vc1.map(&:vc_hash)
  # => ["c9d162308673136bc326be767b111fe9", "ae3813fbddf04017880ec39a25fcc70e"]

  # How the hash was calculated:
  require 'digest/md5'
  vc1[0].tap do |row|
    Digest::MD5.hexdigest row.data  # => "c9d162308673136bc326be767b111fe9"
    row.vc_hash                     # => "c9d162308673136bc326be767b111fe9"
  end

# =====  UPDATE  =====
  sql "update users set name = 'Ashton Bot' where name = 'Ashton'"
  users2 = sql 'select * from users order by id'

  # hashes are updated
  josh1, ashton1 = users1 # => [#<Record id="1" name="Joshua" vc_hash="c9d162308673136bc326be767b111fe9">, #<Record id="2" name="Ashton" vc_hash="ae3813fbddf04017880ec39a25fcc70e">]
  josh2, ashton2 = users2 # => [#<Record id="1" name="Joshua" vc_hash="c9d162308673136bc326be767b111fe9">, #<Record id="2" name="Ashton Bot" vc_hash="99f1dedb09a35fae95d1b1fedee4579f">]

  eq!   josh1.vc_hash,   josh2.vc_hash # => "c9d162308673136bc326be767b111fe9"
  ne! ashton1.vc_hash, ashton2.vc_hash # => "99f1dedb09a35fae95d1b1fedee4579f"

  # updated row is recorded, originals are still there
  vc2 = sql 'select * from vc_rows order by vc_hash'
  eq! vc2.map(&:vc_hash), [josh1, ashton1, ashton2].map(&:vc_hash).sort
  # => ["99f1dedb09a35fae95d1b1fedee4579f",
  #     "ae3813fbddf04017880ec39a25fcc70e",
  #     "c9d162308673136bc326be767b111fe9"]


# =====  UPDATE BACK TO ORIGINAL VALUE  =====
  sql "update users set name = 'Ashton' where name = 'Ashton Bot'"
  users3 = sql 'select * from users order by id'

  # hashes return to old value
  eq! users1, users3

  # update is not recorded, because it already existed
  vc3 = sql 'select * from vc_rows order by vc_hash'
  eq! vc2, vc3
  # => [#<Record vc_hash="99f1dedb09a35fae95d1b1fedee4579f"
  #              tbl="users"
  #              data="\"id\"=>\"2\", \"name\"=>\"Ashton Bot\"">,
  #     #<Record vc_hash="ae3813fbddf04017880ec39a25fcc70e"
  #              tbl="users"
  #              data="\"id\"=>\"2\", \"name\"=>\"Ashton\"">,
  #     #<Record vc_hash="c9d162308673136bc326be767b111fe9"
  #              tbl="users"
  #              data="\"id\"=>\"1\", \"name\"=>\"Joshua\"">]
