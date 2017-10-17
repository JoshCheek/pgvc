require 'pg'

# Reset the database
lambda do
  db = PG.connect dbname: 'postgres'
  db.exec("DROP DATABASE IF EXISTS pg_git;")
  db.exec("CREATE DATABASE pg_git;")
end[]

db = PG.connect dbname: 'pg_git'

# Make the db a little nicer to work with
def db.exec(*)
  super.map { |row| Record.new row }
rescue PG::Error
  $!.set_backtrace caller.drop(1)
  raise
end

class Record
  def initialize(result_hash)
    @hash = result_hash.map { |k, v| [k.intern, v] }.to_h
  end
  def to_h
    @hash.dup
  end
  def ==(other)
    to_h == other.to_h
  end
  def respond_to_missing(name)
    @hash.key? name
  end
  def method_missing(name, *)
    return @hash.fetch name if @hash.key? name
    super
  end
  def inspect
    ::PP.pp(self, '').chomp
  end
  def pretty_print(pp)
    pp.group 2, "#<Record", '>' do
      @hash.each.with_index do |(k, v), i|
        pp.breakable ' '
        pp.text "#{k}=#{v.inspect}"
      end
    end
  end
end


# Some assertion for verifying its behaviour
module Assertions
  def assert(bool, message="failed assertion")
    fail_assertion message unless bool
    bool
  end
  def assert_equal(l, r, message=nil)
    return l if l == r
    fail_assertion "#{message&&message+"\n\n"}Expected #{l.inspect}\nTo Equal #{r.inspect}"
  end
  def refute_equal(l, r, message=nil)
    return [l, r] unless l == r
    fail_assertion "#{message&&message+"\n\n"}Expected      #{l.inspect}\nTo *NOT* Equal #{r.inspect}"
  end
  private def fail_assertion(message)
    err = RuntimeError.new message
    err.set_backtrace caller.drop(1)
    raise err
  end
end
extend Assertions


# The values being stored (going to use their id as the value)
db.exec <<-SQL
  -- version control tables
  create schema version_control;
  set search_path = version_control;
  create table rows (
    vc_hash character(32),
    row     text
  );

  -- the branch (tables we want to put into version control)
  create schema branch1;
  set search_path = branch1, public;
  create table products (
    ID serial primary key,
    name varchar,
    vc_hash character(32)
  );

  -- triggers to calculate the hash
  create or replace function vc_set_hash()
  returns trigger as $$
  begin
    -- When a cast is applied to a value expression of a known type, it represents a run-time type conversion.
    -- :/ means that the memory format would be lost, and values of different types can get conflated
    NEW.vc_hash = null;
    NEW.vc_hash = md5(NEW::text);
    return NEW;
  end $$ language plpgsql;

  create trigger vc_set_hash_insert_tg
    before insert on branch1.products
    for each row execute procedure vc_set_hash();

  create trigger vc_set_hash_update_tg
    before update on branch1.products
    for each row execute procedure vc_set_hash();

  -- trigger to record the insertion
  create or replace function vc_record_row()
  returns trigger as $$
  begin
    insert into version_control.rows (vc_hash)
    select NEW.vc_hash
    where not exists (select vc_hash from version_control.rows where vc_hash = NEW.vc_hash);
    return NEW;
  end $$ language plpgsql;

  create trigger vc_record_row_insert_tg
    after insert on branch1.products
    for each row execute procedure vc_record_row();

  create trigger vc_record_row_update_tg
    after update on branch1.products
    for each row execute procedure vc_record_row();
SQL



# TODO: Two tables with same schema, same col names (maybe it's fine if they match?)
# TODO: Two tables with same schema, different col names (could also be fine to match, if we look up the col names at time of insertion)

# =====  INSERTION  =====
db.exec "insert into branch1.products (name) values ('product 1'), ('product 2')"
products = db.exec 'select * from branch1.products order by id'

# hashes are added
assert_equal products.map { |p| [p.id, p.name] },
             [['1', 'product 1'], ['2', 'product 2']]

refute_equal *products.map(&:vc_hash), 'Hashes differ for different data'
# => ["09707231f1c9f3b821fa24aa72657522", "42a4509accac1698664eae3843d0a473"]

# rows are recorded
vc_rows = db.exec 'select * from version_control.rows'
assert_equal vc_rows.map(&:vc_hash).sort, products.map(&:vc_hash).sort


# =====  UPDATE  =====
db.exec "update branch1.products set name = 'product 1 modified' where name = 'product 1'"
products_mod = db.exec 'select * from branch1.products order by id'

# hashes are updated
assert_equal products_mod.map { |p| [p.id, p.name] },
             [['1', 'product 1 modified'], ['2', 'product 2']]

refute_equal products[0].vc_hash, products_mod[0].vc_hash
# => ["09707231f1c9f3b821fa24aa72657522", "aadfb0ab48a388e90741fdcc59c4a00e"]
assert_equal products[1].vc_hash, products_mod[1].vc_hash
# => "42a4509accac1698664eae3843d0a473"

# updated row is recorded, originals are still there
all_hashes  = [*vc_rows, products_mod[0]].map(&:vc_hash)
vc_rows_mod = db.exec 'select * from version_control.rows'
assert_equal vc_rows_mod.map(&:vc_hash).sort, all_hashes.sort


# =====  UPDATE BACK TO ORIGINAL VALUE  =====
db.exec "update branch1.products set name = 'product 1' where name = 'product 1 modified'"
products_unmod = db.exec 'select * from branch1.products order by id'

# hashes return to old value
assert_equal products, products_unmod

# rows are not recorded, b/c they already exist
vc_rows_unmod = db.exec 'select * from version_control.rows'
assert_equal all_hashes.sort, vc_rows_unmod.map(&:vc_hash).sort
# => ["09707231f1c9f3b821fa24aa72657522",
#     "42a4509accac1698664eae3843d0a473",
#     "aadfb0ab48a388e90741fdcc59c4a00e"]
