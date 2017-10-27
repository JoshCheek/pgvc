require 'pg'
# PG.connect(dbname: 'postgres').exec('drop database josh_testing')
# PG.connect(dbname: 'postgres').exec('create database josh_testing')
db = PG.connect(dbname: 'josh_testing')
db.exec 'begin' # throws away changes when process exits

def db.exec(*)
  super.to_a
end

db.exec <<~SQL
  create function a() returns table(val1 integer, val2 varchar) as $$
    begin
      return query select 1, 'a'::varchar;
      return query select 2, 'b'::varchar;
      return query select 3, 'c'::varchar;
    end $$ language plpgsql;
  select * from a();
  SQL
  # => [{"val1"=>"1", "val2"=>"a"},
  #     {"val1"=>"2", "val2"=>"b"},
  #     {"val1"=>"3", "val2"=>"c"}]
