# Dynamically creating schemas and populating them with tables
require_relative 'helpers'

sql <<~SQL
  create table vc_tracked_tables (name varchar);

  -- two tables to add to a schema
  insert into vc_tracked_tables (name) values ('products'), ('users');

  create table products (
    id   serial primary key,
    name varchar
  );

  create table users (
    id   serial primary key,
    name varchar
  );


  -- To create a branch: create a schema and add the tables to it
  -- Then populate the tables with the rows for the branch's commit
  create function create_branch(in schema_name varchar) returns void as $$
  declare
    table_name varchar;
  begin
    execute format('create schema %s', quote_ident(schema_name));

    for table_name in
      select name from vc_tracked_tables
    loop
      execute format(
        'create table %s.%s (like public.%s including all);',
        quote_ident(schema_name),
        quote_ident(table_name),
        quote_ident(table_name)
      );
    end loop;
  end
  $$ language plpgsql;
SQL


# Create the branch
  sql "select create_branch('mahbranch');"

# It created the schema
  sql "select catalog_name, schema_name from information_schema.schemata where schema_name = 'mahbranch';"
  # => [#<Record catalog_name='pgvc' schema_name='mahbranch'>]

# It created the tables in the schema
  sql "select table_name from information_schema.tables where table_schema = 'mahbranch';"
  # => [#<Record table_name='products'>, #<Record table_name='users'>]
