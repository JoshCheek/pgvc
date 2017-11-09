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
  do $$ begin
    raise notice E'\033[35m%\033[0m', 'this should be magenta!';
    raise notice E'\033[34m%\033[0m', 'this should be blue!';
  end $$ language plpgsql;
  SQL

# !> NOTICE:  \e[35mthis should be magenta!\e[0m

