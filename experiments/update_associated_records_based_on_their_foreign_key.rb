require 'pg'
db = PG.connect(dbname: 'josh_testing')
def db.exec(*)
  super.to_a
end

db.exec 'begin' # throws away changes when process exits
db.exec <<~SQL
  create table users(
    id serial primary key,
    name text
  );
  create table tweets(
    id      serial primary key,
    user_id integer references users (id),
    tweet   text
  );

  insert into users (name) values ('Josh'), ('David'), ('Real Josh');

  insert into tweets (user_id, tweet)
    values (1, 'Josh tweet'), (2, 'David tweet'), (3, 'Real Josh tweet');


  create function move_associated_records(
    table_name  varchar,
    from_rec    anyelement,
    to_rec      anyelement
  ) returns void as $$
    declare
      r record;
    begin
      -- update foreign keys in any associated tables
      for r in
        select tc.table_name as table, kcu.column_name as column, ccu.column_name as fk
        from information_schema.table_constraints       as tc
        join information_schema.key_column_usage        as kcu using (constraint_name)
        join information_schema.constraint_column_usage as ccu using (constraint_name)
        where constraint_type = 'FOREIGN KEY'
        and ccu.table_name = $1
      loop
        execute format(
          'update %I set %I = ($1).%I where %2$I = ($2).%3$I',
          r.table, r.column, r.fk
        ) using to_rec, from_rec;
      end loop;
    end $$ language plpgsql;
  SQL

db.exec 'select name, tweet from users join tweets on (tweets.user_id = users.id)'
# => [{"name"=>"Josh", "tweet"=>"Josh tweet"},
#     {"name"=>"David", "tweet"=>"David tweet"},
#     {"name"=>"Real Josh", "tweet"=>"Real Josh tweet"}]

db.exec <<~SQL
  select move_associated_records(
    'users', -- FIXME: THIS SHOULD BE USERS
    (select users from users where name = 'Josh'),
    (select users from users where name = 'Real Josh')
  );
  SQL

db.exec 'select name, tweet from users join tweets on (tweets.user_id = users.id)'
# => [{"name"=>"David", "tweet"=>"David tweet"},
#     {"name"=>"Real Josh", "tweet"=>"Real Josh tweet"},
#     {"name"=>"Real Josh", "tweet"=>"Josh tweet"}]


