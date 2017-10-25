require 'pg'
# PG.connect(dbname: 'postgres').exec('drop database josh_testing')
# PG.connect(dbname: 'postgres').exec('create database josh_testing')
db = PG.connect(dbname: 'josh_testing')
db.exec 'begin' # throws away changes when process exits

def db.exec(*)
  super.to_a
end

db.exec <<~SQL
  create table strs (
    id  serial,
    val varchar
  );
  insert into strs (val) values ('a'), ('b'), ('c');


  with
    -- some subquery, in our case whatever records are in the from_commit
    sf as (select * from strs where id = 1 or id = 2),

    -- some subquery, in our case, whatever records are in the to_commit
    st as (select * from strs where id = 2 or id = 3),

    -- in from_commit, not in to_commit
    sf_no_st as (
      select sf.*
      from sf
      left join st on (sf.val = st.val)
      where st is null
    ),

    -- in to_commit, not in from_commit
    st_no_sf as (
      select st.*
      from sf
      right join st on (sf.val = st.val)
      where sf is null
    )

    -- delete the ones in from_commit that aren't in to_commit
    select 'delete' as action, * from sf_no_st

    union all

    -- insert the ones in to_commit that aren't in from_commit
    select 'insert', * from st_no_sf;
  SQL
# => [{"action"=>"delete", "id"=>"1", "val"=>"a"},
#     {"action"=>"insert", "id"=>"3", "val"=>"c"}]

