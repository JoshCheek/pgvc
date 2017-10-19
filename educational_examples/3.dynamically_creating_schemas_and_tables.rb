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


  -- The function to add them, "checkout" in git-speak
  create function checkout(in schema_name varchar)
  returns void as $$
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


# "checkout" the schema
  sql "select checkout('mahschema');"

# it was created
  sql "select catalog_name, schema_name from information_schema.schemata where schema_name = 'mahschema';"
  # => [#<Record catalog_name='pg_git' schema_name='mahschema'>]

# tbe table was created
  sql "select table_name from information_schema.tables where table_schema = 'mahschema';"
  # => [#<Record table_name='products'>, #<Record table_name='users'>]
