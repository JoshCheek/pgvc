require 'pg'
# PG.connect(dbname: 'postgres').exec('drop database josh_testing')
# PG.connect(dbname: 'postgres').exec('create database josh_testing')
db = PG.connect(dbname: 'josh_testing')
db.exec 'begin' # throws away changes when process exits

def db.exec(*)
  super.to_a
end

# Schema
  db.exec <<~SQL
    create table vc_rows (
      col_values text
    );

    -- A TABLE WE WANT TO STORE IN VC
    create table users (
      id   serial primary key,
      name varchar
    );
  SQL

# Create some users
  original = db.exec <<~SQL
    insert into users (name)
    values ('Josh'), ('Ashton')
    returning *;
  SQL
  # => [{"id"=>"1", "name"=>"Josh"}, {"id"=>"2", "name"=>"Ashton"}]


# Save the users to version control
  db.exec <<~SQL
    insert into vc_rows (col_values)
    select users::text
    from users
    returning *;
  SQL
  # => [{"col_values"=>"(1,Josh)"}, {"col_values"=>"(2,Ashton)"}]


# Delete the users
  db.exec 'delete from users;'
  db.exec 'select * from users;'
  # => []

# Restore the users from version control
  restored = db.exec <<~SQL
    insert into users
    select (col_values::users).* -- ****EHHHHH!!**** this recasts it for each attr, so it redoes a lot of work
    from vc_rows;

    select * from users;
  SQL

# They match!
  original == restored
  # => true

  original # => [{"id"=>"1", "name"=>"Josh"}, {"id"=>"2", "name"=>"Ashton"}]
  restored # => [{"id"=>"1", "name"=>"Josh"}, {"id"=>"2", "name"=>"Ashton"}]
