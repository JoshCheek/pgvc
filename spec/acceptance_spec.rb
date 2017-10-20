# Using a hypothetical blog (users/posts) to figure out what its behaviour should be and drive its implementation
require 'pgvc'

ROOT_DB = PG.connect dbname: 'postgres'
DBNAME  = 'pgvc_testing'

RSpec.describe 'Figuring out what it should do' do
  attr_reader :client
  before do
    ROOT_DB.exec "drop database if exists #{DBNAME};"
    ROOT_DB.exec "create database #{DBNAME};"

    db = PG.connect dbname: DBNAME
    db.exec <<~SQL
      create table users (
        id serial primary key,
        name varchar
      );
      insert into users (name) values ('system');

      create table products (
        id serial primary key,
        name varchar,
        colour varchar
      );
    SQL
    @client = Pgvc.bootstrap db, system_userid: 1, track: ['products']
  end

  def create_commit(client: self.client, **commit_options)
    commit_options[:synopsis]    ||= 'default synopsis'
    commit_options[:description] ||= 'default description'
    commit_options[:user]        ||= 'default user'
    commit_options[:time]        ||= Time.now
    client.commit! commit_options
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



  describe 'initial state' do
    xit 'starts on the primary branch pointing at the root commit, which is empty' do
      branch = client.branch
      expect(branch.name).to eq 'primary'
      expect(branch.commit.parents).to eq []
    end
  end

  describe 'branches' do
    # probbably the primary branch should jsut be a branch tagged as "default",
    # and should be changeable, but for now, it's not worth the complexity
    it 'can create and delete branches' do
      client.create_branch 'omghi'
      expect(client.branches.map(&:name).sort).to eq ['omghi', 'primary']
      client.delete_branch 'omghi'
    end

    it 'can\'t create a banch with the same name as an existing branch' do
      client.create_branch 'omghi'
      expect { client.create_branch 'omghi' }
        .to raise_error Pgvc::Branch::CannotCreate
    end

    it 'can\'t delete the primary branch' do
      expect { client.delete_branch 'primary' }
        .to raise_error Pgvc::Branch::CannotDelete
    end

    it 'can create a branch pointing to an arbitrary commit'

    it 'remembers which branch it is on' do
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

  describe 'when making changes' do
    # I suppose, ideally, it would record the current user/time when doing this,
    # but I think that would require changes to existing queries
    describe 'via insert' do
      it 'can insert rows and query them back out' do
        expect(client.select_all('products')).to eq [] # =>
        insert_products u1: 'brown', u2: 'green'
        assert_products name: %w[u1 u2], colour: %w[brown green]
      end

      it 'creates a new incomplete commit to hold the changes and points the branch at it' do
        prev = client.commit
        insert_products u1: 'brown'
        crnt = client.commit
        expect(prev.id).to_not eq crnt.id
        expect(prev).to be_complete
        expect(crnt).to_not be_complete
      end

      it 'sets the old commit as a parent of the new commit' do
        prev = client.commit
        insert_products u1: 'brown'
        crnt = client.commit
        expect(prev.parents).to eq []
        expect(crnt.parents).to eq [prev]
      end
    end


    describe 'via update' do
      it 'can update rows and query them backout' do
        insert_products u1: 'brown', u2: 'green', u3: 'cyan'
        client.update 'products', where: {name: 'u2'}, to: {colour: 'magenta'}
        assert_products name: %w[u1 u2 u3], colour: %w[brown magenta cyan]
        client.update 'products', where: {name: 'u3'}, to: {colour: 'black'}
        assert_products name: %w[u1 u2 u3], colour: %w[brown magenta black]
      end

      it 'creates a new incomplete commit to hold the changes and points the branch at it'
        # insert_products u1: 'brown'
        # create_commit

      it 'sets the old commit as a parent of the new commit'
    end


    describe 'via delete' do
      it 'can delete rows, which do not come back out when queried' do
        insert_products u1: 'brown', u2: 'green', u3: 'cyan'

        assert_products name: %w[u1 u2 u3], colour: %w[brown green cyan]
        client.delete 'products', where: {name: 'u2'}
        assert_products name: %w[u1 u3], colour: %w[brown cyan]
        client.delete 'products', where: {name: 'u1'}
        assert_products name: %w[u3], colour: %w[cyan]
        client.delete 'products', where: {name: 'u3'}
        assert_products name: %w[], colour: %w[]
      end

      it 'creates a new incomplete commit to hold the changes and points the branch at it'
      it 'sets the old commit as a parent of the new commit'
    end

    it 'groups all the changes together on the incomplete commit'
  end


  describe 'committing' do
    def assert_commit(commit: client.commit, **assertions)
      assertions.each do |key, value|
        expect(commit[key]).to eq value
      end
    end

    it 'accepts a synopsis, description, user, and time' do
      now = Time.now
      create_commit synopsis:    'the synopsis',
                    description: 'blah blah blah',
                    user:        'josh',
                    time:        now
      assert_commit synopsis:    'the synopsis',
                    description: 'blah blah blah',
                    user:        'josh',
                    time:        now
    end

    describe 'when the commit is incomplete' do
      before do
        insert_products u1: 'brown'
        assert_commit complete?: false
      end

      it 'completes the commit' do
        create_commit
        assert_commit complete?: true
      end

      it 'does not update the branch' do
        prev_id = client.commit.id
        create_commit
        expect(client.commit.id).to eq prev_id
      end
    end

    describe 'when the commit is complete' do
      before { assert_commit complete?: true }
      it 'creates a new complete commit, which is empty' do
        prev = client.commit
        create_commit
        crnt = client.commit

        expect(crnt).to be_complete
        expect(crnt.id).to_not eq prev.id
      end

      it 'makes the old commit a parent of the new commit' do
        prev = client.commit
        create_commit
        crnt = client.commit
        expect(crnt.parents).to eq [prev]
      end
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
