# The purpose of a transaction is to achieve "atomicity", ie the entire operation
# succeeds or fails, all together, without partial updates.
#
# https://www.postgresql.org/docs/9.1/static/sql-set-transaction.html
# https://www.postgresql.org/docs/9.1/static/sql-begin.html
# https://www.postgresql.org/docs/9.1/static/sql-commit.html
# https://www.postgresql.org/docs/9.1/static/sql-rollback.html
# https://www.postgresql.org/docs/9.1/static/sql-savepoint.html
# https://www.postgresql.org/docs/9.1/static/sql-rollback-to.html
# https://www.postgresql.org/docs/9.1/static/sql-release-savepoint.html

require 'pg'
require 'stringio'

PG.connect(dbname: 'postgres')
  .tap { |pg| pg.exec('drop database josh_testing') }
  .tap { |pg| pg.exec('create database josh_testing') }


module DbConvenience
  def shh
    receiver = set_notice_receiver { }
    yield
  ensure
    set_notice_receiver(&receiver)
  end

  def exec(*)
    super.to_a
  rescue
    $!.set_backtrace caller.drop(1)
    raise
  end
end


# A connection that will be making the transaction
trnxn = PG.connect(dbname: 'josh_testing').extend(DbConvenience)

# A connection that represents arbitrary other db connections
world = PG.connect(dbname: 'josh_testing').extend(DbConvenience)


define_singleton_method :reset_strs! do
  world.shh { world.exec <<~SQL }
    create table if not exists strs (val text);
    truncate table strs;
    insert into strs (val) values ('pre');
  SQL
end



# `BEGIN` STARTS A TRANSACTION
  reset_strs!
  trnxn.exec "begin"
  trnxn.exec "insert into strs (val) values ('within')"

  # only trnxn can see its changes
  trnxn.exec "select * from strs" # => [{"val"=>"pre"}, {"val"=>"within"}]
  world.exec "select * from strs" # => [{"val"=>"pre"}]

  trnxn.exec "commit"



# `COMMIT` FINISHES THE TRANSACTION SUCCESSFULLY
  reset_strs!
  trnxn.exec "begin"
  trnxn.exec "insert into strs (val) values ('within')"

  # the world can only see changes after committing
  world.exec "select * from strs" # => [{"val"=>"pre"}]
  trnxn.exec "commit"
  world.exec "select * from strs" # => [{"val"=>"pre"}, {"val"=>"within"}]



# `ROLLBACK` FINISHES THE TRANSACTION UNSUCCESSFULLY
  reset_strs!
  trnxn.exec "begin"
  trnxn.exec "insert into strs (val) values ('within')"

  # changes are discarded
  trnxn.exec "select * from strs" # => [{"val"=>"pre"}, {"val"=>"within"}]
  trnxn.exec "rollback"
  trnxn.exec "select * from strs" # => [{"val"=>"pre"}]



# `SAVEPOINT`S ALLOW PARTIAL ROLLBACKS / PARTIAL COMMITS (kiiiiinda like nested transactions)
  reset_strs!
  # insert 'a' before any savepoints
  trnxn.exec "begin"
  trnxn.exec "insert into strs (val) values ('a')"

  # insert 'b' after the first savepoint
  trnxn.exec "savepoint first"
  trnxn.exec "insert into strs (val) values ('b')"

  # rollback to the first savepoint, 'b' is gone
  trnxn.exec "select * from strs" # => [{"val"=>"pre"}, {"val"=>"a"}, {"val"=>"b"}]
  trnxn.exec "rollback to savepoint first"
  trnxn.exec "select * from strs" # => [{"val"=>"pre"}, {"val"=>"a"}]

  # insert 'c' after the second savepoint
  trnxn.exec "savepoint second"
  trnxn.exec "insert into strs (val) values ('c')"

  # release the second savepoint (like a partial commit)
  # this means we cannot rollback to it anymore, but I'm not going to show
  # that b/c it breaks the rest of the transaction
  trnxn.exec "select * from strs" # => [{"val"=>"pre"}, {"val"=>"a"}, {"val"=>"c"}]
  trnxn.exec "release savepoint second"
  trnxn.exec "select * from strs" # => [{"val"=>"pre"}, {"val"=>"a"}, {"val"=>"c"}]

  # the rest of the world can see the data inserted in the transaction after the final commit
  world.exec "select * from strs" # => [{"val"=>"pre"}]
  trnxn.exec "commit"
  world.exec "select * from strs" # => [{"val"=>"pre"}, {"val"=>"a"}, {"val"=>"c"}]



# `TRANSACTION ISOLATION LEVEL READ COMMITTED` (DEFAULT) ALLOWS IT TO SEE THE WORLD'S CHANGES
  reset_strs!
  trnxn.exec "begin"

  # can see the world's changes
  trnxn.exec "select * from strs" # => [{"val"=>"pre"}]
  world.exec "insert into strs (val) values ('within')"
  trnxn.exec "select * from strs" # => [{"val"=>"pre"}, {"val"=>"within"}]

  trnxn.exec "commit"



# `TRANSACTION ISOLATION LEVEL: REPEATABLE READ` HIDES THE WORLD'S CHANGES UNTIL DONE
  reset_strs!
  trnxn.exec "begin transaction isolation level repeatable read"

  # cannot see the world's changes
  trnxn.exec "select * from strs" # => [{"val"=>"pre"}]
  world.exec "insert into strs (val) values ('within')"
  trnxn.exec "select * from strs" # => [{"val"=>"pre"}]

  # until after commit
  trnxn.exec "commit"
  trnxn.exec "select * from strs" # => [{"val"=>"pre"}, {"val"=>"within"}]



# NUANCE TO `REPEATABLE READ`: THE ISOLATION DOESN'T START UNTIL THE FIRST STATEMENT
  reset_strs!
  trnxn.exec "begin transaction isolation level repeatable read"

  # can see the world's changes made before this first select
  world.exec "insert into strs (val) values ('within-first')"
  trnxn.exec "select * from strs" # => [{"val"=>"pre"}, {"val"=>"within-first"}]

  # but not before this second select
  world.exec "insert into strs (val) values ('within-second')"
  trnxn.exec "select * from strs" # => [{"val"=>"pre"}, {"val"=>"within-first"}]

  # until after commit
  trnxn.exec "commit"
  trnxn.exec "select * from strs" # => [{"val"=>"pre"}, {"val"=>"within-first"}, {"val"=>"within-second"}]
