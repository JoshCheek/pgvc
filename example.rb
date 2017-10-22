# Reset the database
require 'pg'
PG.connect(dbname: 'postgres')
  .tap { |db| db.exec 'drop database if exists pgvc_testing' }
  .tap { |db| db.exec 'create database pgvc_testing' }
db = PG.connect dbname: 'pgvc_testing'

# Create users and products
  db.exec <<~SQL
    SET client_min_messages=WARNING;

    create table users (
      id serial primary key,
      name varchar
    );
    insert into users (name)
      values ('josh'), ('lucy'), ('system');

    create table products (
      id serial primary key,
      name varchar,
      colour varchar
    );
    insert into products (name, colour)
      values ('boots', 'black');
  SQL

# Load the library
  $LOAD_PATH.unshift File.expand_path('lib', __dir__)
  require 'pgvc'

# Pull our users out
  josh, lucy, system =
    db.exec("select * from users order by name;").map { |r| Pgvc::Record.new r }
    # => [#<Record id="1" name="josh">,
    #     #<Record id="2" name="lucy">,
    #     #<Record id="3" name="system">]

# Add version control to the database
  pgvc = Pgvc.bootstrap db, system_userid: system.id, track: ['products'], default_branch: 'trunk'

# Josh is on the default branch, "trunk", which is in the "public" schema
  trunk = pgvc.get_branch josh.id
  # => #<Record id="1"
  #             commit_hash="c8bd3f0ff47acd5ec2fe58ad4ed14518"
  #             name="trunk"
  #             schema_name="public"
  #             is_default="t">

# The trunk is pointing at the initial commit, created by the system user
  pgvc.get_commit trunk.commit_hash
  # => #<Record vc_hash="c8bd3f0ff47acd5ec2fe58ad4ed14518"
  #             db_hash=nil
  #             user_id="3"
  #             summary="Initial commit"
  #             description=""
  #             created_at="2017-10-21 19:30:13.044801">

# Josh commits the boots
  pgvc.create_commit summary: 'Add pre-existing products', description: '', user_id: josh.id, created_at: Time.now

# Trunk has been updated to the new commit
  trunk  = pgvc.get_branch josh.id
  commit = pgvc.get_commit trunk.commit_hash
  # => #<Record vc_hash="1bafd33ecd6e5616fe9867bbe101ca04"
  #             db_hash="fdad56fe1d8185215bb1da4441c5f5b2"
  #             user_id="1"
  #             summary="Add pre-existing products"
  #             description=""
  #             created_at="2017-10-21 19:30:13">

# Josh makes a new branch and updates the colour of the boots
  pgvc.create_branch_from_current 'update-boots', josh.id
  pgvc.switch_branch josh.id, 'update-boots'
  pgvc.connection_for('update-boots').exec("update products set colour = 'brown'")

# Lucy, still on the trunk branch, makes a new branch and adds shoes
  pgvc.create_branch_from_current 'add-shoes', lucy.id
  pgvc.switch_branch lucy.id, 'add-shoes'
  pgvc.connection_for('add-shoes')
      .exec("insert into products (name, colour) values ('shoes', 'white')")

# What do the products look like on the different branches?
  pgvc.connection_for('update-boots').exec('select * from products').to_a
  # => [{"id"=>"1", "name"=>"boots", "colour"=>"brown", "vc_hash"=>nil}]
  pgvc.connection_for('add-shoes').exec('select * from products').to_a
  # => [{"id"=>"1", "name"=>"boots", "colour"=>"black", "vc_hash"=>nil},
  #     {"id"=>"2", "name"=>"shoes", "colour"=>"white", "vc_hash"=>nil}]
  pgvc.connection_for('trunk').exec('select * from products').to_a
  # => [{"id"=>"1",
  #      "name"=>"boots",
  #      "colour"=>"black",
  #      "vc_hash"=>"b95fcc685e439417cae418e97366685c"}]

# Josh and Lucy both commit
  pgvc.create_commit summary: 'Boots are brown', description: '', user_id: josh.id, created_at: Time.now
  pgvc.create_commit summary: 'Add shoes', description: '', user_id: lucy.id, created_at: Time.now

# Then, idk, merging or diffing or something
