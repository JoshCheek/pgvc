# https://www.postgresql.org/docs/9.6/static/ddl-inherit.html
# https://www.postgresql.org/docs/9.6/static/sql-createtable.html

require 'pg'
# PG.connect(dbname: 'postgres').exec('drop database josh_testing')
# PG.connect(dbname: 'postgres').exec('create database josh_testing')
db = PG.connect(dbname: 'josh_testing')
db.exec 'begin' # throws away changes when process exits
def db.exec(*)
  super.to_a
end

db.exec <<~SQL
  create table parent (
    id serial primary key,
    name varchar
  );

  -- The difference between the two below is that inheritance causes:
  -- queries against the parent will return results from the child
  -- schema changes to the parent will apply to the child

  create table child_inherits () inherits (parent);
  create table child_like     (like parent including all);

  insert into parent         (name) values ('a'), ('b');
  insert into child_inherits (name) values ('c'), ('d');
  insert into child_like     (name) values ('e'), ('f');
  SQL


# =====  Child results  =====
# Note that querying the parent returns results from child_inherits (*not* child_like)
db.exec 'select * from parent'      # => [{"id"=>"1", "name"=>"a"}, {"id"=>"2", "name"=>"b"}, {"id"=>"3", "name"=>"c"}, {"id"=>"4", "name"=>"d"}]

# We can omit them with the "only" keyword
db.exec 'select * from only parent' # => [{"id"=>"1", "name"=>"a"}, {"id"=>"2", "name"=>"b"}]

# We can set "only" as the default with a sql_inheritance
db.exec 'set sql_inheritance = off'
db.exec 'select * from parent'      # => [{"id"=>"1", "name"=>"a"}, {"id"=>"2", "name"=>"b"}]

# When this default is set, query children with an asterisk
db.exec 'select * from parent*'     # => [{"id"=>"1", "name"=>"a"}, {"id"=>"2", "name"=>"b"}, {"id"=>"3", "name"=>"c"}, {"id"=>"4", "name"=>"d"}]


# =====  Changing the parent schema  =====
# When we change the parent, child_inherits is changed, child_like is not
db.exec 'alter table parent* rename name to xxxx'
db.exec 'select * from parent'         # => [{"id"=>"1", "xxxx"=>"a"}, {"id"=>"2", "xxxx"=>"b"}]
db.exec 'select * from child_inherits' # => [{"id"=>"3", "xxxx"=>"c"}, {"id"=>"4", "xxxx"=>"d"}]
db.exec 'select * from child_like'     # => [{"id"=>"5", "name"=>"e"}, {"id"=>"6", "name"=>"f"}]


# =====  Uniqueness constraints  =====
db.exec <<~SQL
  create function try_insert(
    in table_name     varchar,
    in id             integer,
    in name           varchar,
    out success       boolean,
    out error_message text
  ) as $$
    begin
      success := true;
      execute
        format('insert into %I values ($1, $2)', table_name)
        using id, name;
    exception when unique_violation then
      success := false;
      error_message := 'unique_violation';
    end $$ language plpgsql;


  create function primary_keys(table_name varchar) returns text as $$
    select format_type(a.atttypid, a.atttypmod) as data_type
    from   pg_index i
    join   pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
    where  i.indrelid = table_name::regclass
    and    i.indisprimary;
    $$ language sql;
  SQL


# Inserting into parent with 1 (parent pk), 3 (child_inherits pk), and 5 (child_like pk)
db.exec "select * from try_insert('parent', 1, 'dup')" # => [{"success"=>"f", "error_message"=>"unique_violation"}]
db.exec "select * from try_insert('parent', 3, 'dup')" # => [{"success"=>"t", "error_message"=>nil}]
db.exec "select * from try_insert('parent', 5, 'dup')" # => [{"success"=>"t", "error_message"=>nil}]

# Inserting into child_inherits with 1 (parent pk), 3 (child_inherits pk), and 5 (child_like pk)
# Here, we see that the uniqueness constraint was not copied to child_inherits
db.exec "select * from try_insert('child_inherits', 1, 'dup')" # => [{"success"=>"t", "error_message"=>nil}]
db.exec "select * from try_insert('child_inherits', 3, 'dup')" # => [{"success"=>"t", "error_message"=>nil}]
db.exec "select * from try_insert('child_inherits', 5, 'dup')" # => [{"success"=>"t", "error_message"=>nil}]

# Inserting into child_like with 1 (parent pk), 3 (child_inherits pk), and 5 (child_like pk)
db.exec "select * from try_insert('child_like', 1, 'dup')" # => [{"success"=>"t", "error_message"=>nil}]
db.exec "select * from try_insert('child_like', 3, 'dup')" # => [{"success"=>"t", "error_message"=>nil}]
db.exec "select * from try_insert('child_like', 5, 'dup')" # => [{"success"=>"f", "error_message"=>"unique_violation"}]

# Why did child_inherits work, where the others did not? Because it lost the pk & uniqueness constraints:
db.exec "select * from primary_keys('parent')"         # => [{"primary_keys"=>"integer"}]
db.exec "select * from primary_keys('child_like')"     # => [{"primary_keys"=>"integer"}]
db.exec "select * from primary_keys('child_inherits')" # => [{"primary_keys"=>nil}]
