require 'pg'
require 'stringio'

PG.connect(dbname: 'postgres')
  .tap { |pg| pg.exec('drop database josh_testing') }
  .tap { |pg| pg.exec('create database josh_testing') }


module DbConvenience
  def exec(*)
    super.to_a
  rescue
    $!.set_backtrace caller.drop(1)
    raise
  end
end


db1 = PG.connect(dbname: 'josh_testing').extend(DbConvenience)
db2 = PG.connect(dbname: 'josh_testing').extend(DbConvenience)

db1.exec <<~SQL
  create table if not exists strs (val text);
  insert into strs (val) values ('pre');
  SQL


# ON COLLISION, THE SECOND ONE GETS BLOCKED UNTIL THE FIRST COMMITS
  db1.exec 'begin'
  db2.exec 'begin'

  db1.exec 'select * from strs' # => [{"val"=>"pre"}]
  db2.exec 'select * from strs' # => [{"val"=>"pre"}]

  db1.exec "update strs set val = '1'"
  order = Queue.new
  thread = Thread.new do
    order << :pre_db2_update
    db2.exec "update strs set val = '2'"
    order << :post_db2_update
  end

  order << :pre_pass
  Thread.pass
  order << :post_pass1

  order << :pre_sleep
  sleep 1
  order << :post_sleep

  order << :pre_db1_commit
  db1.exec 'commit'
  order << :post_db1_commit

  db1.exec 'select * from strs' # => [{"val"=>"1"}]
  db2.exec 'select * from strs' # => [{"val"=>"2"}]

  order << :pre_db1_join
  thread.join
  order << :post_db1_join

  db2.exec 'commit'
  db1.exec 'select * from strs' # => [{"val"=>"2"}]
  db2.exec 'select * from strs' # => [{"val"=>"2"}]

  # Db2 goes to update, but gets blocked and control is returned to main thread
  # until db1 finishes updating. Once it is done, db2 proceeds to execute the
  # db2's update, essentially causing it to behave as if its update happeend
  # after db1 finished doing its thing.
  #
  # Most important bit: `:post_db2_update` does not occur until after `:post_db1_commit`
  until order.length == 0 && order.num_waiting == 0
    order.pop
    # => :pre_pass
    #    ,:pre_db2_update
    #    ,:post_pass1
    #    ,:pre_sleep
    #    ,:post_sleep
    #    ,:pre_db1_commit
    #    ,:post_db1_commit
    #    ,:post_db2_update
    #    ,:pre_db1_join
    #    ,:post_db1_join
  end
