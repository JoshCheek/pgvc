require 'pg'
db = PG.connect(dbname: 'josh_testing')
# PG.connect(dbname: 'postgres').exec('drop database josh_testing')
# PG.connect(dbname: 'postgres').exec('create database josh_testing')
db.exec 'begin' # throws away changes when process exits

def db.exec(*)
  super.to_a
rescue Exception
  $!.set_backtrace caller.drop(1)
  raise
end


db.exec <<~SQL
  create function time_query(in sql text, out duration interval) as $$
    declare
      start_time timestamp;
      stop_time  timestamp;
    begin
      start_time := clock_timestamp();
      execute sql;
      stop_time := clock_timestamp();
      duration := age(stop_time, start_time);
    end $$ language plpgsql;


  select time_query($$
    select pg_sleep(2)
  $$);
  SQL
  # => [{"time_query"=>"00:00:02.073698"}]

