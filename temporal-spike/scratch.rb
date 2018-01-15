require 'pg'
require 'awesome_print'
dbname = 'pgvc_temporal_test'
# PG.connect(dbname: 'postgres').exec("drop database #{dbname}")
# PG.connect(dbname: 'postgres').exec("create database #{dbname}")

db = PG.connect(dbname: dbname)

db.exec <<~SQL
create schema if not exists pgvc_temporal;

create or replace function
  pgvc_temporal.bootstrap(schemaname text)
  returns void as $$
  begin
--    execute format('ALTER SCHEMA %I RENAME TO %I_versions;', schemaname, schemaname);
--    execute format('CREATE SCHEMA %I;', schemaname);
    execute format('FOR tableName IN
                            SELECT table_name FROM INFORMATION_SCHEMA.TABLES WHERE table_schema = \'%I_versions\'
                        LOOP
                            CREATE OR REPLACE VIEW format(\'%I.\%\I\',tableName.table_name) AS
                            SELECT * FROM format(\'%I_versions.\%\I\',tableName.table_name)
                        END LOOP;', schemaname, schemaname, schemaname);
    -- later: create the variable that stores the "effective time"
  end $$ language plpgsql;
SQL


  def show(db)
    cats  = db.exec('select * from test1.categories').to_a
    prods = db.exec('select * from test1.products').to_a
    ap categories: cats, products: prods
  end

  def insert(db, tables)
    sql = ''
    tables.each do |table, records|
      records.map do |record|
        sql << "insert into test1.#{table} (#{record.keys.join(',')}) values (#{record.values.join(',')});"
      end
    end
    db.exec sql
  end

# Setup
def setup(db)
    db.exec <<~SQL
    create schema test1;
    -- set search_path = test1;

    create table test1.categories (
        id           serial primary key,
        name         text,
        is_preferred boolean
    );

    create table test1.products (
        id          serial primary key,
        name        text,
        colour      text,
        category_id integer references test1.categories(id)
    );
    SQL

    # Pre-existing data
    insert db,
        categories: [
        {name: "'electrical'", is_preferred: false},
        {name: "'plumbing'",   is_preferred: true},
        {name: "'blasting'",   is_preferred: false},
        ],
        products: [
        {name: "'wire'", colour: "'green'",         category_id: 1},
        {name: "'bulb'", colour: "'bright'",        category_id: 1},
        {name: "'pipe'", colour: "'pipe-coloured'", category_id: 2},
        ]

end
# Test
# call the bootstrap fn
db.exec "select pgvc_temporal.bootstrap('test1')"

# for each table
#   add it to temporal vc
db.exec "select pgvc_temporal.add_versioning_to_table('test1', 'categories')"
db.exec "select pgvc_temporal.add_versioning_to_table('test1', 'products')"

# I can still select/insert/update/delete to that table

# I set my time to the past
# I see the past data when I select
# I can no longer insert / update / delete

show db
