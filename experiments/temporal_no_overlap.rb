require 'pg'
# PG.connect(dbname: 'postgres').exec('drop database josh_testing')
# PG.connect(dbname: 'postgres').exec('create database josh_testing')

is_parent = fork

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
  create table room_reservation (
    room text,
    during tsrange,
    exclude using gist (room with =, during with &&)
  );
  SQL

db.exec <<~SQL
  insert into room_reservation
    values ('123A', '[2010-01-01 14:00, 2010-01-01 15:00)')
    returning *
  SQL
  # => [{"room"=>"123A",
  #      "during"=>"[\"2010-01-01 14:00:00\",\"2010-01-01 15:00:00\")"}]
  #    ,[{"room"=>"123A",
  #      "during"=>"[\"2010-01-01 14:00:00\",\"2010-01-01 15:00:00\")"}]

if is_parent
  begin
    db.exec <<~SQL
      insert into room_reservation
        values ('123A', '[2010-01-01 14:30, 2010-01-01 15:30)')
      SQL
  rescue PG::ExclusionViolation
    $! # => #<PG::ExclusionViolation: ERROR:  conflicting key value violates exclusion constraint "room_reservation_room_during_excl"\nDETAIL:  Key (room, during)=(123A, ["2010-01-01 14:30:00","2010-01-01 15:30:00")) conflicts with existing key (room, during)=(123A, ["2010-01-01 14:00:00","2010-01-01 15:00:00")).\n>
  end
else
  db.exec <<~SQL
    insert into room_reservation values
      ('123B', '[2010-01-01 14:30, 2010-01-01 15:30)')
      returning *
    SQL
    # => [{"room"=>"123B",
    #      "during"=>"[\"2010-01-01 14:30:00\",\"2010-01-01 15:30:00\")"}]
end

