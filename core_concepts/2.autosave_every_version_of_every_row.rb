# How to hash and backup every state of every record
require_relative 'helpers'

# Tables and Trigger
  sql <<~SQL
    -- version controlled rows
    create extension hstore;
    create table vc_rows (
      vc_hash character(32) primary key,
      col_values hstore
    );

    -- record changes to this table
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
      NEW.vc_hash := md5(serialized::text);
      insert into vc_rows (vc_hash, col_values)
        select NEW.vc_hash, serialized
        on conflict do nothing;
      return NEW;
    end $$ language plpgsql;

    -- Hash and store on every insert / update
    create trigger vc_hash_and_record_tg
      before insert or update on users
      for each row execute procedure vc_hash_and_record();
  SQL


# =====  INSERTION  =====
  # adds hashes them and saves them into the version controlled rows table
  users1 = sql "insert into users (name) values ('Divya'), ('Darby') returning *"
  # => [#<Record id='1' name='Divya' vc_hash='c7a727b3c2e2fd691ef33eaa23ba9981'>,
  #     #<Record id='2' name='Darby' vc_hash='7a3310ec4414b76ea5633cbab642ac9d'>]

  vc1 = sql 'select * from vc_rows'
  # => [#<Record vc_hash='c7a727b3c2e2fd691ef33eaa23ba9981' col_values='"id"=>"1", "name"=>"Divya"'>,
  #     #<Record vc_hash='7a3310ec4414b76ea5633cbab642ac9d' col_values='"id"=>"2", "name"=>"Darby"'>]

  eq! users1.map(&:vc_hash), vc1.map(&:vc_hash)
  # => ['c7a727b3c2e2fd691ef33eaa23ba9981', '7a3310ec4414b76ea5633cbab642ac9d']

  # How the hash was calculated:
  require 'digest/md5'
  Digest::MD5.hexdigest vc1[0].col_values # => 'c7a727b3c2e2fd691ef33eaa23ba9981'
  vc1[0].vc_hash                          # => 'c7a727b3c2e2fd691ef33eaa23ba9981'

# =====  UPDATE  =====
  sql "update users set name = 'Darby😜' where name = 'Darby'"
  users2 = sql 'select * from users order by id'

  # hashes are updated
  divya1, darby1 = users1 # => [#<Record id='1' name='Divya' vc_hash='c7a727b3c2e2fd691ef33eaa23ba9981'>, #<Record id='2' name='Darby' vc_hash='7a3310ec4414b76ea5633cbab642ac9d'>]
  divya2, darby2 = users2 # => [#<Record id='1' name='Divya' vc_hash='c7a727b3c2e2fd691ef33eaa23ba9981'>, #<Record id='2' name='Darby😜' vc_hash='52c38b2824600ac5257e1ccb566d2e2d'>]

  eq! divya1.vc_hash, divya2.vc_hash # => 'c7a727b3c2e2fd691ef33eaa23ba9981'
  ne! darby1.vc_hash, darby2.vc_hash # => '52c38b2824600ac5257e1ccb566d2e2d'

  # updated row is recorded, originals are still there
  vc2 = sql 'select * from vc_rows order by vc_hash'
  eq! vc2.map(&:vc_hash), [divya1, darby1, darby2].map(&:vc_hash).sort
  # => ['52c38b2824600ac5257e1ccb566d2e2d',
  #     '7a3310ec4414b76ea5633cbab642ac9d',
  #     'c7a727b3c2e2fd691ef33eaa23ba9981']


# =====  UN-UPDATE (SET BACK TO ORIGINAL VALUE)  =====
  sql "update users set name = 'Darby' where name = 'Darby😜'"
  users3 = sql 'select * from users order by id'

  # hashes return to old value
  eq! users1, users3

  # update is not recorded, because it already existed
  vc3 = sql 'select * from vc_rows order by vc_hash'
  eq! vc2, vc3
  # => [#<Record vc_hash='52c38b2824600ac5257e1ccb566d2e2d' col_values='"id"=>"2", "name"=>"Darby😜"'>,
  #     #<Record vc_hash='7a3310ec4414b76ea5633cbab642ac9d' col_values='"id"=>"2", "name"=>"Darby"'>,
  #     #<Record vc_hash='c7a727b3c2e2fd691ef33eaa23ba9981' col_values='"id"=>"1", "name"=>"Divya"'>]
