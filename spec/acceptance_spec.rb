# Using a hypothetical blog (users/posts) to figure out what its behaviour should be and drive its implementation
require 'pgvc'

ROOT_DB = PG.connect dbname: 'postgres'
DBNAME  = 'pgvc_testing'

RSpec.describe 'Figuring out what it should do' do
  attr_reader :db, :client, :user

  before do
    ROOT_DB.exec "drop database if exists #{DBNAME};"
    ROOT_DB.exec "create database #{DBNAME};"
    @db = PG.connect dbname: DBNAME
    db.exec <<~SQL
      create table users (
        id serial primary key,
        name varchar
      );
      insert into users (name) values ('system'), ('josh');

      create table products (
        id serial primary key,
        name varchar,
        colour varchar
      );

      SET client_min_messages=WARNING;
    SQL
    users   = sql "select * from users;"
    @user   = users.find { |u| u.name == 'josh' }
    system  = users.find { |u| u.name == 'system' }
    before_bootstrap
    @client = Pgvc.bootstrap db,
                system_userid:  system.id,
                track:          ['products'],
                default_branch: 'trunk' # I dislike "master" as the default branch name
  end

  after { db.finish }

  def before_bootstrap
    # noop, override in children if necessary
  end

  def sql1(sql, *params)
    sql(sql, *params).first
  end

  def sql(sql, *params)
    if params.empty?
      db.exec sql
    else
      db.exec_params sql, params
    end.map { |row| Pgvc::Record.new row }
  end

  def create_commit(client: self.client, **commit_options)
    commit_options[:summary]     ||= 'default summary'
    commit_options[:description] ||= 'default description'
    commit_options[:user_id]     ||= user.id
    commit_options[:created_at]  ||= Time.now
    client.create_commit commit_options
  end

  def insert_products(products, client: self.client)
    products.each do |key, value|
      client.insert 'products', name: key.to_s, colour: value
    end
  end

  def assert_products(assertions, client: self.client)
    results = client.select_all 'products'
    assertions.each do |key, values|
      expect(pluck results, key).to eq values
    end
  end

  def pluck(hashes, key)
    hashes.map { |hash| hash.fetch key }
  end



  # Dump as much shit into a given test as we can since they're so expensive
  describe 'initial state' do
    def before_bootstrap
      sql "insert into products (name, colour) values ('boots', 'black')"
    end

    it 'starts on the default branch pointing at the root commit, using the public schema, and tracks the tables' do
      # -- branch / commit --
      # user is on a branch (the default branch)
      branch = client.get_branch user.id
      expect(branch.name).to eq 'trunk'

      # the default branch corresponds to the public schema
      expect(branch.schema_name).to eq 'public'

      # it is pointing at the initial commit
      commit = client.get_commit branch.commit_hash
      expect(commit.summary).to match /initial commit/i

      # -- tracked tables --
      # added vc_rows and calculated it for existing records
      boots = sql1 "select * from products"
      expect(boots.vc_hash.length).to eq 32

      # updates their hash on insert / update
      shoes1 = sql1 "insert into products (name, colour) values ('shoes', 'blue') returning *"
      shoes2 = sql1 "update products set colour = 'yellow' returning *"
      expect(shoes1.vc_hash).to_not eq shoes2.vc_hash

      # all of these values are saved
      hashes = sql("select vc_hash from vc.rows").map(&:vc_hash)
      expect(hashes).to include boots.vc_hash
      expect(hashes).to include shoes1.vc_hash
      expect(hashes).to include shoes2.vc_hash
    end

    # FIXME: should it add the tables?... probably :/
  end


  describe 'branches' do
    it 'can create, rename, and delete branches' do
      client.create_branch_from_current 'omghi', user.id
      expect(client.get_branches.map(&:name).sort).to eq ['omghi', 'trunk']
      client.rename_branch 'omghi', 'lolol'
      expect(client.get_branches.map(&:name).sort).to eq ['lolol', 'trunk']
      client.delete_branch 'lolol'
      expect(client.get_branches.map(&:name).sort).to eq ['trunk']
    end

    it 'knows which branch a user is on, and allows them to switch to a different branch' do
      client.create_branch_from_current 'other', user.id
      expect(client.get_branch(user.id).name).to eq 'trunk'
      client.switch_branch user.id, 'other'
      expect(client.get_branch(user.id).name).to eq 'other'
    end

    xit 'creates a schema for the given branch sets its tables and rows up to match the given commit' do
      sql "insert into products (name, colour) values ('boots', 'black')"
      commit1 = create_commit summary: 'boots', user_id: user.id
      client.create_branch_from_current 'boots', user.id

      sql "insert into products (name, colour) values ('shoes', 'blue')"
      commit2 = create_commit summary: 'boots and shoes', user_id: user.id
      client.create_branch_from_current 'boots+shoes', user.id

      client.create_branch_from_current 'mahbrnach', user.id
    end

    it 'can have crazy branch names (spaces, commas, etc)' do
      name = %q_abc[]{}"' ~!@\#$%^&*()+_
      client.create_branch_from_current name, user.id
      expect(client.get_branches.map(&:name).sort).to eq [name, 'trunk']
      skip
      schemas = sql "select * from information_schema.schemata;"
      require "pry"
      binding.pry
    end

    it 'can\'t create a branch with the same name as an existing branch' do
      client.create_branch 'omghi'
      expect { client.create_branch 'omghi' }
        .to raise_error Pgvc::Branch::CannotCreate
    end

    it 'can\'t delete the primary branch' do
      expect { client.delete_branch 'trunk' }
        .to raise_error Pgvc::Branch::CannotDelete
    end

    it 'can create a branch pointing to an arbitrary commit'

    it 'remembers which branch a user is on' do
      client.create_branch 'other'
      expect(client.branch.name).to eq 'primary'
      client.switch_branch 'other'
      expect(client.branch.name).to eq 'other'
    end

    it 'returns to the primary branch when it deletes the branch it is on' do
      client.create_branch 'crnt'
      client.create_branch 'other'
      client.switch_branch 'crnt'

      # branch stays the same b/c other got deleted
      expect(client.branch.name).to eq 'crnt'
      client.delete_branch 'other'
      expect(client.branch.name).to eq 'crnt'

      # branch changes b/c crnt got deleted
      client.delete_branch 'crnt'
      expect(client.branch.name).to eq 'primary'
    end
  end


  describe 'committing' do
    def assert_commit(commit:, **assertions)
      assertions.each do |key, value|
        expect(commit[key]).to eq value
      end
    end

    it 'accepts a summary, description, user_id, and created_at' do
      now = Time.now
      commit = create_commit summary:     'the summary',
                             description: 'blah blah blah',
                             user_id:     user.id,
                             created_at:  now
      assert_commit commit:      commit,
                    summary:     'the summary',
                    description: 'blah blah blah',
                    user_id:     user.id,
                    created_at:  now.strftime('%F %T') # FIXME: should convert to zulu?
    end

    it 'makes the old commit a parent of the new commit and updates the branch' do
      branch = client.get_branch(user.id)
      prev   = client.get_commit branch.commit_hash

      commit = create_commit

      branch = client.get_branch(user.id)
      crnt   = client.get_commit branch.commit_hash

      expect(crnt).to eq commit
      expect(client.get_parents crnt.vc_hash).to eq [prev]
    end
  end

  describe 'history' do
    # should probably be able to set a branch at an arbitrary commit, but I'll deal w/ it later
    it 'displays the database as it looks from a given branch' do
      client.create_branch 'a'
      client.create_branch 'b'

      client.switch_branch 'a'
      insert_products product_a: 'colour_a'

      client.switch_branch 'b'
      assert_products name: %w[]
      insert_products product_b: 'colour_b'

      client.create_branch 'c'
      client.switch_branch 'c'
      client.update 'products', with: {name: 'product_b'}, to: {colour: 'colour_c'}

      client.switch_branch 'a'
      assert_products name: %w[product_a], colour: %w[colour_a]
      client.switch_branch 'b'
      assert_products name: %w[product_b], colour: %w[colour_b]
      client.switch_branch 'c'
      assert_products name: %w[product_b], colour: %[colour_c]
    end
  end

  describe 'working on a branch' do
    def before_bootstrap
      sql "insert into products (name, colour) values ('a', 'a')"
    end
    it 'applies those changes to only that branch' do
      create_commit
      client.create_branch_from_current 'other', user.id
      client.connection_for('trunk').exec("insert into products (name, colour) values ('b', 'b')")
      client.connection_for('other').exec("insert into products (name, colour) values ('c', 'c')")
      trunk_products = client.connection_for('trunk').exec("select * from products").map { |r| r['name'] }
      other_products = client.connection_for('other').exec("select * from products").map { |r| r['name'] }
      expect(trunk_products).to eq ['a', 'b']
      expect(other_products).to eq ['a', 'c']
    end
  end

  describe 'diffing returns the set of changes between two commits' do
    example 'an empty commit'
    example 'insertions'
    example 'deletions'
    example 'updates'
    example 'inserting and then deleting has no diff'
    example 'inserting and updating is just inserting'
    example 'updating and updating is just updating (for whichever came last)'
    example 'updating and deleting is just a deletinv'
  end
end
