require 'pg'
require 'awesome_print'
dbname = 'pgvc_temporal_test'
# PG.connect(dbname: 'postgres').exec("drop database #{dbname}")
# PG.connect(dbname: 'postgres').exec("create database #{dbname}")

db = PG.connect(dbname: dbname)
db.exec File.read(File.expand_path '../lib/omg.pls', __dir__)


RSpec.describe 'acceptance test' do
  around do |spec|
    db.exec 'begin'
    spec.call
    db.exec 'rollback'
  end

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

    # Test
    # version the schema
    db.exec "select pgvc_temporal.addVersioningToSchema('test1')"

    # I can still select/insert/update/delete to that table
    # I set my time to the past
    # I see the past data when I select
    # I can no longer insert / update / delete

    show db
  end
end
