# How to hash and backup every state of the record

require_relative 'helpers'

sql <<~SQL
  -- version controlled rows
  create extension hstore;
  create table vc_rows (
    vc_hash character(32),
    tbl     varchar,
    data    hstore
  );

  create table products (
    id      serial primary key,
    name    varchar,
    vc_hash character(32)
  );

  -- triggers to calculate the hash
  create or replace function vc_hash_and_record()
  returns trigger as $$
  declare
    serialized hstore;
  begin
    NEW.vc_hash = null;
    select hstore(NEW) into serialized;
    NEW.vc_hash = md5(serialized::text);

    insert into vc_rows (vc_hash, tbl, data)
    select NEW.vc_hash, TG_TABLE_NAME, serialized
    where not exists (select vc_hash from vc_rows where vc_hash = NEW.vc_hash);

    return NEW;
  end $$ language plpgsql;

  create trigger vc_hash_and_record_tg
    before insert or update on products
    for each row execute procedure vc_hash_and_record();
SQL


# =====  INSERTION  =====
# adds hashes them and saves them into the version controlled rows table
products1 = sql <<~SQL
  insert into products (name)
  values ('product 1'), ('product 2')
  returning *;
  SQL
  # => [#<Record
  #       id="1"
  #       name="product 1"
  #       vc_hash="9eaeba201e14817d2a06b7e9ebc10fb9">,
  #     #<Record
  #       id="2"
  #       name="product 2"
  #       vc_hash="d0025370dea0817b3cb818cfb31be348">]

vcrows1 = sql 'select * from vc_rows'
  # => [#<Record
  #       vc_hash="9eaeba201e14817d2a06b7e9ebc10fb9"
  #       tbl="products"
  #       data="\"id\"=>\"1\", \"name\"=>\"product 1\", \"vc_hash\"=>NULL">,
  #     #<Record
  #       vc_hash="d0025370dea0817b3cb818cfb31be348"
  #       tbl="products"
  #       data="\"id\"=>\"2\", \"name\"=>\"product 2\", \"vc_hash\"=>NULL">]

products1.map(&:vc_hash) # => ["9eaeba201e14817d2a06b7e9ebc10fb9", "d0025370dea0817b3cb818cfb31be348"]
vcrows1.map(&:vc_hash)   # => ["9eaeba201e14817d2a06b7e9ebc10fb9", "d0025370dea0817b3cb818cfb31be348"]

# How the hash was calculated:
require 'digest/md5'
vcrows1[0].tap do |row|
  Digest::MD5.hexdigest row.data  # => "9eaeba201e14817d2a06b7e9ebc10fb9"
  row.vc_hash                     # => "9eaeba201e14817d2a06b7e9ebc10fb9"
end

# =====  UPDATE  =====
sql "update products set name = 'product 1a' where name = 'product 1'"
products2 = sql 'select * from products order by id'

# hashes are updated
products1 # => [#<Record id="1" name="product 1" vc_hash="9eaeba201e14817d2a06b7e9ebc10fb9">, #<Record id="2" name="product 2" vc_hash="d0025370dea0817b3cb818cfb31be348">]
products2 # => [#<Record id="1" name="product 1a" vc_hash="f04740f3f269e47aa74106eaa3ce76d5">, #<Record id="2" name="product 2" vc_hash="d0025370dea0817b3cb818cfb31be348">]

ne! products1[0].vc_hash, products2[0].vc_hash # => "f04740f3f269e47aa74106eaa3ce76d5"
eq! products1[1].vc_hash, products2[1].vc_hash # => "d0025370dea0817b3cb818cfb31be348"

# updated row is recorded, originals are still there
vcrows2 = sql 'select * from vc_rows'
eq! vcrows2.map(&:vc_hash).sort,
    [*products1, *products2].map(&:vc_hash).uniq.sort
    # => ["9eaeba201e14817d2a06b7e9ebc10fb9",
    #     "d0025370dea0817b3cb818cfb31be348",
    #     "f04740f3f269e47aa74106eaa3ce76d5"]


# =====  UPDATE TO ORIGINAL VALUE  =====
sql "update products set name = 'product 1' where name = 'product 1a'"
products3 = sql 'select * from products order by id'

# hashes return to old value
eq! products1, products3

# update is not recorded, because it already existed
vcrows3 = sql 'select * from vc_rows'
eq! vcrows2, vcrows3
