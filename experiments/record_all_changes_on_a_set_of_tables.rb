require 'pg'
require 'erb'

# db = PG.connect(dbname: 'postgres')
# db.exec 'drop database josh_testing'
# db.exec 'create database josh_testing'

# =====  Setup  =====
db = PG.connect(dbname: 'josh_testing')
db.exec 'begin' # discard changes

def db.exec(*)
  super.to_a
rescue
  $!.set_backtrace caller.drop(1)
  raise
end


# =====  Helpers  =====
public def headerify(column_name)
  column_name.tr('_', ' ').split.map(&:capitalize).join(' ')
end

public def as_history
  keys       = at(0).keys.map { |key| " #{headerify key} " }
  valuess    = map(&:values).map { |values| values.map { |val| " #{val} " } }
  lengths    = [keys, *valuess].transpose.map { |cols| cols.map(&:length).max }
  separators = lengths.map { |l| "-" * l }
  format_str = lengths.map { |l| "%-#{l}s" }.join("|")
  [ format_str%keys,
    (format_str%separators).gsub("|", "+"),
    *valuess.map { |values| format_str % values }
  ]
end


# =====  Schema  =====
db.exec <<~SQL
  -- Two tables to track
  create table strings (
    id serial primary key,
    val text
  );

  create schema mahschema;
  create table mahschema.users (
    id serial primary key,
    name text,
    created_at timestamp default now()
  );

  -- The tables we are tracking
  create table tracked_tables (
    schema_name text,
    table_name  text,
    unique (schema_name, table_name)
  );
  insert into tracked_tables select 'public',    'strings';
  insert into tracked_tables select 'mahschema', 'users';

  -- The table that tracks the changes
  create table history (
    changed_at  timestamp,
    schema_name text,
    table_name  text,
    type        text,
    record      text
  );


  -- The function that tracks them
  create function track_changes() returns trigger as $$
    declare
      rec record;
    begin
      if TG_OP = 'DELETE' then
        rec = OLD;
      else
        rec = NEW;
      end if;

      insert into history select now(), TG_TABLE_SCHEMA, TG_RELNAME, TG_OP, rec::text;

      return rec;
    end $$ language plpgsql;


  -- Dynamically add a trigger that calls the function whenever there is an insert / update / delete
  -- NOTE: we can also set "truncate" here, but I haven't explored what that does
  -- NOTE: do we want to set deferrable on this? what does deferrable do?
  do $body$
  declare
    schema_name text;
    table_name  text;
  begin
    for schema_name, table_name in select t.schema_name, t.table_name from tracked_tables t
    loop
      execute format(
        $$ create trigger track_changes_trigger
           before insert or update or delete
           on %I.%I
           for each row execute procedure track_changes();
        $$, schema_name, table_name
      );
    end loop;
  end $body$ language plpgsql;
  SQL


# =====  Insert / Update / Delete some rows  =====
db.exec(<<~SQL)
  insert into strings (val)
    values ('a'), ('b'), ('c');

  select * from strings;
  SQL
  # => [{"id"=>"1", "val"=>"a"},
  #     {"id"=>"2", "val"=>"b"},
  #     {"id"=>"3", "val"=>"c"}]


db.exec(<<~SQL)
  update strings
    set val = upper(val)
    where val != 'a';

  select * from strings;
  SQL
  # => [{"id"=>"1", "val"=>"a"},
  #     {"id"=>"2", "val"=>"B"},
  #     {"id"=>"3", "val"=>"C"}]


db.exec(<<~SQL)
  delete
    from strings
    where val = 'C';

  select * from strings;
  SQL
  # => [{"id"=>"1", "val"=>"a"}, {"id"=>"2", "val"=>"B"}]


db.exec <<~SQL
  insert into mahschema.users (name) values ('Josh'), ('Matt'), ('Divya');
  select * from mahschema.users;
  SQL
  # => [{"id"=>"1", "name"=>"Josh", "created_at"=>"2017-11-21 10:46:30.4819"},
  #     {"id"=>"2", "name"=>"Matt", "created_at"=>"2017-11-21 10:46:30.4819"},
  #     {"id"=>"3", "name"=>"Divya", "created_at"=>"2017-11-21 10:46:30.4819"}]

db.exec <<~SQL
  delete from mahschema.users where name = 'Josh';
  select * from mahschema.users;
  SQL
  # => [{"id"=>"2", "name"=>"Matt", "created_at"=>"2017-11-21 10:46:30.4819"},
  #     {"id"=>"3", "name"=>"Divya", "created_at"=>"2017-11-21 10:46:30.4819"}]


# =====  The Result  =====
db.exec(<<~SQL).as_history
  select * from history;
  SQL
  # => [" Changed At               | Schema Name | Table Name | Type   | Record                               ",
  #     "--------------------------+-------------+------------+--------+--------------------------------------",
  #     " 2017-11-21 10:46:30.4819 | public      | strings    | INSERT | (1,a)                                ",
  #     " 2017-11-21 10:46:30.4819 | public      | strings    | INSERT | (2,b)                                ",
  #     " 2017-11-21 10:46:30.4819 | public      | strings    | INSERT | (3,c)                                ",
  #     " 2017-11-21 10:46:30.4819 | public      | strings    | UPDATE | (2,B)                                ",
  #     " 2017-11-21 10:46:30.4819 | public      | strings    | UPDATE | (3,C)                                ",
  #     " 2017-11-21 10:46:30.4819 | public      | strings    | DELETE | (3,C)                                ",
  #     " 2017-11-21 10:46:30.4819 | mahschema   | users      | INSERT | (1,Josh,\"2017-11-21 10:46:30.4819\")  ",
  #     " 2017-11-21 10:46:30.4819 | mahschema   | users      | INSERT | (2,Matt,\"2017-11-21 10:46:30.4819\")  ",
  #     " 2017-11-21 10:46:30.4819 | mahschema   | users      | INSERT | (3,Divya,\"2017-11-21 10:46:30.4819\") ",
  #     " 2017-11-21 10:46:30.4819 | mahschema   | users      | DELETE | (1,Josh,\"2017-11-21 10:46:30.4819\")  "]

