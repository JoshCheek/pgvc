require 'pg'
# PG.connect(dbname: 'postgres').exec('drop database josh_testing')
# PG.connect(dbname: 'postgres').exec('create database josh_testing')

db = PG.connect(dbname: 'josh_testing')
db.exec 'begin' # throws away changes when process exits

def db.exec(*)
  super.to_a
rescue Exception
  $!.set_backtrace caller.drop(1)
  raise
end

db.exec <<~SQL
  create extension btree_gist;
  create table products (
    name text unique,
    assert_time timestamp default now(),
    retract_time timestamp
  );
  insert into products
    values ('wire', '2010-01-01 14:00', '2010-01-01 15:00'),
           ('pipe', '2010-01-01 14:00', '2010-01-01 15:00')
    returning *;
  SQL
  # => [{"name"=>"wire",
  #      "assert_time"=>"2010-01-01 14:00:00",
  #      "retract_time"=>"2010-01-01 15:00:00"},
  #     {"name"=>"pipe",
  #      "assert_time"=>"2010-01-01 14:00:00",
  #      "retract_time"=>"2010-01-01 15:00:00"}]

## ????
db.exec <<~SQL
  -- select * from information_schema.table_constraints where table_name = 'products';
  alter table products drop constraint products_name_key;
  alter table products add constraint products_name_key_temporal
    exclude using gist
    ( name WITH =,
      tsrange(assert_time, retract_time, '[)') WITH &&   -- this is the crucial
    );
  SQL

# PROFIT
db.exec <<~SQL
  insert into products
    values ('wire', '2010-01-01 15:00', '2010-01-01 16:00')
    returning *
  SQL
  # => [{"name"=>"wire",
  #      "assert_time"=>"2010-01-01 15:00:00",
  #      "retract_time"=>"2010-01-01 16:00:00"}]

begin
  db.exec <<~SQL
    insert into products
      values ('wire', '2010-01-01 15:30', '2010-01-01 17:00')
      returning *
    SQL
rescue PG::ExclusionViolation => err
  err.message # => "ERROR:  conflicting key value violates exclusion constraint \"products_name_key_temporal\"\nDETAIL:  Key (name, tsrange(assert_time, retract_time, '[)'::text))=(wire, [\"2010-01-01 15:30:00\",\"2010-01-01 17:00:00\")) conflicts with existing key (name, tsrange(assert_time, retract_time, '[)'::text))=(wire, [\"2010-01-01 15:00:00\",\"2010-01-01 16:00:00\")).\n"
else
  raise "No error!!"
end
