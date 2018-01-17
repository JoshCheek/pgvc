require 'spec_helper'


RSpec.describe 'acceptance test' do
  def reset_db
    db.exec <<~SQL
    drop schema if exists test1 cascade;
    drop schema if exists test1_versions cascade;

    create schema if not exists test1;
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

    db.exec sql_library_code
  end

  before :each do
    reset_db
  end

  it 'can put an existing db into temporal version control' do
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

    # TODO: I can no longer insert / update / delete

    # show_view db
    # show_versions db

    # TODO:
    #   fix the primary key and foreign key constraints
  end


  if private_fixture_info = ENV['PRIVATE_FIXTURES_INFO']
    file, schema = private_fixture_info.split(":")
    it 'works for all the fixture schemas' do
      sql = File.read file
      db.exec %'drop schema if exists "#{schema}" cascade'
      db.exec %'create schema "#{schema}"'
      db.exec sql
      db.exec "select pgvc_temporal.add_versioning_to_schema('#{schema}')"
    end
  end
end
