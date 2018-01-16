require 'pg'
require 'awesome_print'
dbname = 'pgvc_temporal_test'
# PG.connect(dbname: 'postgres').exec("drop database #{dbname}")
# PG.connect(dbname: 'postgres').exec("create database #{dbname}")

db = PG.connect(dbname: dbname)
db.exec <<~SQL
  drop schema if exists test1 cascade;
  drop schema if exists test1_versions cascade;
SQL
db.exec File.read(File.expand_path '../lib/pgvc_temporal.pls', __dir__)


RSpec.describe 'acceptance test' do
  def show_view(db)
    cats  = db.exec('select * from test1.categories').to_a
    prods = db.exec('select * from test1.products').to_a
    ap categories: cats, products: prods
  end

  def show_versions(db)
    cats  = db.exec('select * from test1_versions.categories').to_a
    prods = db.exec('select * from test1_versions.products').to_a
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


  def update(db, tables)
    sql = ''
    tables.each do |table, updates|
      updates.map do |update|
        update = update.dup
        id = update.delete :id
        update_sql = update.map { |k, v| "#{k} = #{v}" }.join(" ")
        sql << "update test1.#{table} set #{update_sql} where id = #{id};"
      end
    end
    db.exec sql
  end


  def delete(db, tables)
    sql = ''
    tables.each do |table, ids|
      sql << "delete from test1.#{table} where id in (#{ids.join(", ")});"
    end
    db.exec sql
  end

  def now(db)
    db.exec('select current_timestamp')[0].values.first
  end

  def assert_rows(db, table_assertions)
    table_assertions.each do |table, row_assertions|
      actual_rows = db.exec("select * from test1.#{table}").map(&:to_h)
      expected_rows = row_assertions.map do |row_assertion|
        row_assertion.map { |k, v| [k.to_s, v.to_s] }.to_h
      end
      actual_rows.sort_by! { |row| row['id'].to_i }
      expected_rows.sort_by! { |row| row['id'].to_i }
      expect(actual_rows).to eq expected_rows
    end
  end


  it 'can put an existing db into temporal version control' do
    # Setup
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

    # Version the schema
    db.exec "select pgvc_temporal.add_versioning_to_schema('test1')"

    # Test

    # Before modification
    assert_rows db,
      categories: [
        {id: 1, name: 'electrical', is_preferred: 'f'},
        {id: 2, name: 'plumbing',   is_preferred: 't'},
        {id: 3, name: 'blasting',   is_preferred: 'f'},
      ],
      products: [
        {id: 1, name: 'wire', colour: 'green',         category_id: 1},
        {id: 2, name: 'bulb', colour: 'bright',        category_id: 1},
        {id: 3, name: 'pipe', colour: 'pipe-coloured', category_id: 2},
      ]

    t1 = now db
    insert db, products: [{name: "'tv'", colour: "'black'", category_id: 1}] # insert
    t2 = now db
    update db, products: [{id: 3, colour: "'rust'"}] # update
    t3 = now db
    delete db, products: [2] # delete
    t4 = now db

    # After modification
    assert_rows db,
      categories: [
        {id: 1, name: 'electrical', is_preferred: 'f'},
        {id: 2, name: 'plumbing',   is_preferred: 't'},
        {id: 3, name: 'blasting',   is_preferred: 'f'},
      ],
      products: [
        {id: 1, name: 'wire', colour: 'green', category_id: 1},
        {id: 3, name: 'pipe', colour: 'rust',  category_id: 2},
        {id: 4, name: 'tv',   colour: 'black', category_id: 1},
      ]

    # View data before modifications
    db.exec "select pgvc_temporal.timetravel_to('#{t1}')"
    assert_rows db,
      categories: [
        {id: 1, name: 'electrical', is_preferred: 'f'},
        {id: 2, name: 'plumbing',   is_preferred: 't'},
        {id: 3, name: 'blasting',   is_preferred: 'f'},
      ],
      products: [
        {id: 1, name: 'wire', colour: 'green',         category_id: 1},
        {id: 2, name: 'bulb', colour: 'bright',        category_id: 1},
        {id: 3, name: 'pipe', colour: 'pipe-coloured', category_id: 2},
      ]

    # I see the past data when I select
    # I can no longer insert / update / delete
    # show_view db
    # show_versions db
  end
end
