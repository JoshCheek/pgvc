# Reset the database
  require 'pg'
  PG.connect(dbname: 'postgres')
    .tap { |db| db.exec 'drop database if exists pgvc_testing' }
    .tap { |db| db.exec 'create database pgvc_testing' }
  db = PG.connect dbname: 'pgvc_testing'

# Create users and products
  db.exec <<~SQL
    SET client_min_messages=WARNING;
    create table products (
      id serial primary key,
      name varchar,
      colour varchar
    );
  SQL

# Load the lib
  $LOAD_PATH.unshift File.expand_path('lib', __dir__)
  require 'pgvc/git'
  Pgvc.init db, default_branch: 'master'

  git = Pgvc::Git.new db

# Some local work
  git.exec "insert into products (name, colour) values ('boots', 'black')"

# Initialize git
  git.config_user_ref 'Josh Cheek'
  git.init

# Add existing products
  git.add_table 'products'
  git.commit 'Add pre-existing products'

# Check the log history
  git.log.map { |log| [log.summary, log.user_ref] }
  # => [["Add pre-existing products", "Josh Cheek"]]

# 1 branch, master, which we are on
  git.branch.map { |b| [b.name, b.current?] } # => [["master", true]]

# Make a new branch and check it out
  git.branch 'add-shoes'
  git.branch.map { |b| [b.name, b.current?] } # => [["add-shoes", false], ["master", true]]
  git.checkout 'add-shoes'
  git.branch.map { |b| [b.name, b.current?] } # => [["add-shoes", true], ["master", false]]

# Same history
  git.log.map { |log| [log.summary, log.user_ref] }
  # => [["Add pre-existing products", "Josh Cheek"]]

# Add some white shoes
  git.exec "insert into products (name, colour) values ('shoes', 'white')"
  git.log.map { |log| [log.summary, log.user_ref] }
  # => [["Add pre-existing products", "Josh Cheek"]]
  git.commit 'Add white shoes'
  git.log.map { |log| [log.summary, log.user_ref] }
  # => [["Add white shoes", "Josh Cheek"],
  #     ["Add pre-existing products", "Josh Cheek"]]

# Products on our branch vs master
  git.exec('select id, name, colour from products order by id')
  # => [#<Record id="1" name="boots" colour="black">,
  #     #<Record id="2" name="shoes" colour="white">]
  git.checkout 'master'
  git.exec('select id, name, colour from products order by id')
  # => [#<Record id="1" name="boots" colour="black">]

# Log from our branch vs master
  git.log.map { |log| [log.summary, log.user_ref] }
  # => [["Add pre-existing products", "Josh Cheek"]]
  git.checkout 'add-shoes'
  git.log.map { |log| [log.summary, log.user_ref] }
  # => [["Add white shoes", "Josh Cheek"],
  #     ["Add pre-existing products", "Josh Cheek"]]

# Fast-forward merge
  git.checkout 'master'
  git.merge 'add-shoes'
  git.log.map { |log| [log.summary, log.user_ref] }
  # => [["Add white shoes", "Josh Cheek"],
  #     ["Add pre-existing products", "Josh Cheek"]]
  git.exec('select * from products').map { |p| [p.id, p.name, p.colour] }
  # => [["1", "boots", "black"], ["2", "shoes", "white"]]
