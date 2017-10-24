# Using a hypothetical blog (users/posts) to figure out what its behaviour should be and drive its implementation
require 'pgvc'
require 'spec_helper'

RSpec.describe 'Figuring out what it should do' do
  attr_reader :db, :client, :user

  before { ROOT_DB.exec 'select reset_test_db()' }

  before do
    @db = PG.connect dbname: DBNAME
    db.exec <<~SQL
      SET client_min_messages=WARNING;

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
    SQL
    @user, system  = sql "select * from users;"
    before_init
    # I dislike "master" as the default branch name
    @client = Pgvc.init db, system_user_ref: system.id, default_branch: 'trunk'
    @client.track_table 'products'
  end

  def before_init
    # noop, override in children if necessary
  end

  def sql1(sql, *params, **options)
    sql(sql, *params, **options).first
  end

  def sql(sql, *params, db: get_db(user))
    if params.empty?
      db.exec sql # prefer exec as it is more permissive
    else
      db.exec_params sql, params
    end.map { |row| Pgvc::Record.new row }
  end

  def get_db(user)
    return self.db unless user && client
    branch = client.user_get_branch user.id
    client.connection_for(branch.name)
  end

  def create_commit(client: self.client, **commit_options)
    commit_options[:summary]     ||= 'default summary'
    commit_options[:description] ||= 'default description'
    commit_options[:user_ref]    ||= user.id
    commit_options[:created_at]  ||= Time.now
    client.create_commit commit_options
  end

  def insert_products(products, client: self.client)
    products.each do |key, value|
      sql 'insert into products (name, colour) values ($1, $2)', key, value
    end
  end

  def assert_products(assertions, client: self.client)
    results = sql('select * from products')
    assertions.each do |key, values|
      expect(pluck results, key).to eq values
    end
  end

  def pluck(records, key)
    records.map { |record| record[key] }
  end



  # Dump as much shit into a given test as we can since they're so expensive
  describe 'initial state' do
    def before_init
      sql "insert into products (name, colour) values ('boots', 'black')"
    end

    it 'starts on the default branch pointing at the root commit, using the public schema, and tracks the tables' do
      # -- branch / commit --
      # user is on a branch (the default branch)
      branch = client.user_get_branch user.id
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
      client.user_create_branch 'omghi', user.id
      expect(client.get_branches.map(&:name).sort).to eq ['omghi', 'trunk']
      client.rename_branch 'omghi', 'lolol'
      expect(client.get_branches.map(&:name).sort).to eq ['lolol', 'trunk']
      client.delete_branch 'lolol'
      expect(client.get_branches.map(&:name).sort).to eq ['trunk']
    end

    it 'knows which branch a user is on, and allows them to switch to a different branch' do
      client.user_create_branch 'other', user.id
      expect(client.user_get_branch(user.id).name).to eq 'trunk'
      client.switch_branch user.id, 'other'
      expect(client.user_get_branch(user.id).name).to eq 'other'
    end

    xit 'creates a schema for the given branch sets its tables and rows up to match the given commit' do
      sql "insert into products (name, colour) values ('boots', 'black')"
      commit1 = create_commit summary: 'boots', user_ref: user.id
      client.user_create_branch 'boots', user.id

      sql "insert into products (name, colour) values ('shoes', 'blue')"
      commit2 = create_commit summary: 'boots and shoes', user_ref: user.id
      client.user_create_branch 'boots+shoes', user.id

      client.user_create_branch 'mahbrnach', user.id
    end

    it 'can have crazy branch names (spaces, commas, etc)' do
      name = %q_abc[]{}"' ~!@\#$%^&*()+_
      client.user_create_branch name, user.id
      client.switch_branch user.id, name
      sql "insert into products (name, colour) values ('a','a')"
      assert_products name: %w[a]
      client.switch_branch user.id, 'trunk'
      assert_products name: %w[]
    end

    it 'can\'t create a branch with the same name as an existing branch' do
      client.user_create_branch 'omghi', user.id
      expect { client.user_create_branch 'omghi', user.id }
        .to raise_error PG::UniqueViolation
    end

    it 'can\'t delete the default branch' do
      expect { client.delete_branch 'trunk' }
        .to raise_error PG::DataException
    end

    it 'can create a branch pointing to an arbitrary commit'

    it 'remembers which branch a user is on' do
      client.user_create_branch 'other', user.id
      expect(client.user_get_branch(user.id).name).to eq 'trunk'
      client.switch_branch user.id, 'other'
      expect(client.user_get_branch(user.id).name).to eq 'other'
    end

    it 'returns a user to the primary branch when it deletes the branch it is on' do
      client.user_create_branch 'crnt',  user.id
      client.user_create_branch 'other', user.id
      client.switch_branch user.id, 'crnt'

      # branch stays the same b/c other got deleted
      expect(client.user_get_branch(user.id).name).to eq 'crnt'
      client.delete_branch 'other'
      expect(client.user_get_branch(user.id).name).to eq 'crnt'

      # branch changes b/c crnt got deleted
      client.delete_branch 'crnt'
      expect(client.user_get_branch(user.id).name).to eq 'trunk'
    end
  end


  describe 'committing' do
    def assert_commit(commit:, **assertions)
      assertions.each do |key, value|
        expect(commit[key]).to eq value
      end
    end

    it 'accepts a summary, description, user_ref, and created_at' do
      now = Time.now
      commit = create_commit summary:     'the summary',
                             description: 'blah blah blah',
                             user_ref:    user.id,
                             created_at:  now
      assert_commit commit:      commit,
                    summary:     'the summary',
                    description: 'blah blah blah',
                    user_ref:    user.id,
                    created_at:  now.strftime('%F %T') # FIXME: should convert to zulu?
    end

    it 'makes the old commit a parent of the new commit and updates the branch' do
      branch = client.user_get_branch(user.id)
      prev   = client.get_commit branch.commit_hash

      commit = create_commit

      branch = client.user_get_branch(user.id)
      crnt   = client.get_commit branch.commit_hash

      expect(crnt).to eq commit
      expect(client.get_parents crnt.vc_hash).to eq [prev]
    end
  end

  describe 'history' do
    # should probably be able to set a branch at an arbitrary commit, but I'll deal w/ it later
    it 'displays the database as it looks from a given branch' do
      client.user_create_branch 'a', user.id
      client.user_create_branch 'b', user.id

      client.switch_branch user.id, 'a'
      insert_products product_a: 'colour_a'
      create_commit

      client.switch_branch user.id, 'b'
      assert_products name: %w[]
      insert_products product_b: 'colour_b'
      create_commit

      client.user_create_branch 'c', user.id
      client.switch_branch user.id, 'c'
      get_db(user).exec "update products set colour = 'colour_c' where name = 'product_b'"

      client.switch_branch user.id, 'a'
      assert_products name: %w[product_a], colour: %w[colour_a]
      client.switch_branch user.id, 'b'
      assert_products name: %w[product_b], colour: %w[colour_b]
      client.switch_branch user.id, 'c'
      assert_products name: %w[product_b], colour: %w[colour_c]
    end
  end

  describe 'working on a branch' do
    def before_init
      sql "insert into products (name, colour) values ('a', 'a')"
    end
    it 'applies those changes to only that branch' do
      create_commit
      client.user_create_branch 'other', user.id
      client.connection_for('trunk').exec("insert into products (name, colour) values ('b', 'b')")
      client.connection_for('other').exec("insert into products (name, colour) values ('c', 'c')")
      trunk_products = client.connection_for('trunk').exec("select * from products")
      other_products = client.connection_for('other').exec("select * from products")
      expect(trunk_products.map { |r| r['name'] }).to eq ['a', 'b']
      expect(other_products.map { |r| r['name'] }).to eq ['a', 'c']
      expect([*trunk_products, *other_products].map { |r| r['vc_hash'] })
        .to_not be_any &:nil?
    end
  end

  describe 'diffing returns the set of changes between two commits', t:true do
    example 'an empty commit' do
      branch = client.user_get_branch user.id
      old    = client.get_commit branch.commit_hash
      new    = create_commit
      expect(old).to_not eq new
      diff = client.diff old.vc_hash, new.vc_hash
      expect(diff).to eq []
    end

    example 'insertions'
    example 'deletions'
    example 'updates'
    example 'inserting and then deleting has no diff'
    example 'inserting and updating is just inserting'
    example 'updating and updating is just updating (for whichever came last)'
    example 'updating and deleting is just a deletinv'
  end
end
