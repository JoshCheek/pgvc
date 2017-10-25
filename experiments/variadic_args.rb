require 'pg'
# PG.connect(dbname: 'postgres').exec('drop database josh_testing')
# PG.connect(dbname: 'postgres').exec('create database josh_testing')
db = PG.connect(dbname: 'josh_testing')
db.exec 'begin' # throws away changes when process exits

def db.exec(*)
  super.to_a
end

db.exec <<~SQL
  create function a() returns varchar as $$
    begin
      return 'none';
    end $$ language plpgsql;

  create function a(variadic args varchar[]) returns varchar as $$
    begin
      return array_length(args, 1)::text||': '||args::text;
    end $$ language plpgsql;

  select a()              as first,
         a('b')           as second,
         a('b', 'c')      as third,
         a('b', 'c', 'd') as fourth;
  SQL
  # => [{"first"=>"none",
  #      "second"=>"1: {b}",
  #      "third"=>"2: {b,c}",
  #      "fourth"=>"3: {b,c,d}"}]

