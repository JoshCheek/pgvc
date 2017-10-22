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
  pgvc = Pgvc.bootstrap db, system_userid: system.id, default_branch: 'master'

# Josh is on the default branch, "master", which is in the "public" schema
  master = pgvc.get_branch josh.id
  # => #<Record id="1"
  #             commit_hash="695993188132d3b2de0639dcd825d1f2"
  #             name="master"
  #             schema_name="public"
  #             is_default="t">

# Master is pointing at the initial commit, created by the system user
  pgvc.get_commit master.commit_hash
  # => #<Record vc_hash="695993188132d3b2de0639dcd825d1f2"
  #             db_hash=nil
  #             user_id="3"
  #             summary="Initial commit"
  #             description=""
  #             created_at="2017-10-22 12:39:36.898678">

# Tell pgvc to track the products table
  pgvc.track_table 'products'

# Josh commits the boots
  pgvc.create_commit summary: 'Add pre-existing products', user_id: josh.id

# Master has been updated to the new commit
  master = pgvc.get_branch josh.id
  commit = pgvc.get_commit master.commit_hash
  # => #<Record vc_hash="b890568a19a7fd5ffaaf316bb855fafb"
  #             db_hash="fdad56fe1d8185215bb1da4441c5f5b2"
  #             user_id="1"
  #             summary="Add pre-existing products"
  #             description=""
  #             created_at="2017-10-22 07:13:42">

# Josh makes a new branch and updates the colour of the boots
  pgvc.create_branch_from_current 'update-boots', josh.id
  pgvc.switch_branch josh.id, 'update-boots'
  pgvc.connection_for('update-boots').exec("update products set colour = 'brown'")
  pgvc.connection_for('update-boots').exec('select * from products').to_a
  # => [{"id"=>"1",
  #      "name"=>"boots",
  #      "colour"=>"brown",
  #      "vc_hash"=>"9df1cc901a477daa1bc6f22b45225494"}]

# Lucy, still on the master branch, makes a new branch and adds shoes
  pgvc.create_branch_from_current 'add-shoes', lucy.id
  pgvc.switch_branch lucy.id, 'add-shoes'
  pgvc.connection_for('add-shoes')
      .exec("insert into products (name, colour) values ('shoes', 'white')")
  pgvc.connection_for('add-shoes').exec('select * from products').to_a
  # => [{"id"=>"1",
  #      "name"=>"boots",
  #      "colour"=>"black",
  #      "vc_hash"=>"b95fcc685e439417cae418e97366685c"},
  #     {"id"=>"2",
  #      "name"=>"shoes",
  #      "colour"=>"white",
  #      "vc_hash"=>"4e87ce327c3d158a57dd9198bd010575"}]

# And the master branch reflects neither of these changes
  pgvc.connection_for('master').exec('select * from products').to_a
  # => [{"id"=>"1",
  #      "name"=>"boots",
  #      "colour"=>"black",
  #      "vc_hash"=>"b95fcc685e439417cae418e97366685c"}]

# Josh and Lucy both commit
  update_boots = pgvc.create_commit summary: 'Boots are brown', description: '', user_id: josh.id, created_at: Time.now
  add_shoes    = pgvc.create_commit summary: 'Add shoes', description: '', user_id: lucy.id, created_at: Time.now
  pgvc.history_from update_boots.vc_hash # ~> NoMethodError: undefined method `history_from' for #<Pgvc:0x007faf23913b18>
  # =>
  pgvc.history_from add_shoes.vc_hash
  # =>

# Then, idk, merging or diffing or something

# ~> NoMethodError
# ~> undefined method `history_from' for #<Pgvc:0x007faf23913b18>
# ~>
# ~> /Users/xjxc322/code/pgvc/example.rb:78:in `<main>'
