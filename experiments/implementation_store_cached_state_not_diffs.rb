# A branch is a pointer to a commit
# A commit is a hashed database, author, commit message, and date
# A database is a hashed list of tables
# A table is a hashed structure and list of rows (or row sets as an optimization detail?)
# A table structure is a hashed list of columns
# A a column is a name and hashed type
# A type is a postgresql type and modifiers
# A row is a list of cells that line up with the table's structure
# A cell is a hashed database value
# A value is a postgresql row in a table of values of that type

# When a commit is made, hash each of these all the way down (prob needs some optimization detail),
# for anything whose hash isn't recorded, store it.
#
# The diff between two commits can be identified by looking at their hashes to see where they diverge,
# just follow it down.
#
# To build an arbitrary database state, rebuild by looking up the pieces based on their hashes


# Reset and connect to the database
require 'pg'
db = PG.connect(dbname: 'postgres')
db.exec("DROP DATABASE IF EXISTS pg_git;")
db.exec("CREATE DATABASE pg_git;")
db = PG.connect dbname: 'pg_git'

# The tables
db.exec <<-SQL
  CREATE TABLE users (
    id        serial primary key,
    username  varchar,
    branch_id int default 1 -- 1 is the id of the primary branch
  );
  -- Commit: a group of changes (deltas)
  CREATE TABLE commits (
    id           serial primary key,
    author_id    int,
    description  varchar default '',
    details      text default '',
    created_at   timestamp default now(),
    committed_at timestamp,
    database:
  );
  -- Ancestry: relationship between commits
  CREATE TABLE ancestry (
    parent_id int,
    child_id  int
  );
  -- Branch: a name for a commit
  -- these will be used to track which commits we are interested in viewing and editing
  -- eg branches will be cached, where commits won't, because there would be too many of them
  CREATE TABLE branches (
    id         serial primary key,
    name       varchar,
    commit_id  int,
    created_at timestamp default now(),
    creator_id int -- a user
  );
SQL

(db.exec "select table_name from information_schema.tables where table_schema = 'public'").to_a
# => [{"table_name"=>"users"},
#     {"table_name"=>"commits"},
#     {"table_name"=>"ancestry"},
#     {"table_name"=>"branches"}]


__END__
# Initial version control data
# system user
system_user = db.exec_params(<<-SQL, ['system']).first
  INSERT INTO users (username) VALUES ($1) RETURNING *;
SQL

# root commit
root_commit = db.exec_params(
  'INSERT INTO commits (author_id, description, details, committed_at) VALUES ($1, $2, $3, now()) RETURNING *;',
  [ system_user['id'],
    'Root Commit',
    'The parent commit that all future commits will be based off of'
  ]
).first

# trunk branch
trunk_branch = db.exec_params(
  'INSERT INTO branches (name, commit_id, creator_id) VALUES ($1, $2, $3) RETURNING *',
  ['trunk', root_commit['id'], system_user['id']]
).first

# the system user is on the trunk branch
system_user = db.exec(<<-SQL, [trunk_branch['name'], system_user['id']]).first
  UPDATE users SET branch_name = $1 WHERE id = $2 RETURNING *;
SQL

db.exec('SELECT * FROM users;').to_a # => [{"id"=>"1", "username"=>"system", "branch_name"=>"trunk"}]
db.exec('SELECT * FROM commits;').to_a # => [{"id"=>"1", "author_id"=>"1", "description"=>"Root Commit", "details"=>"The parent commit that all future commits will be based off of", "created_at"=>"2017-10-06 20:39:01.795668", "committed_at"=>"2017-10-06 20:39:01.795668"}]
db.exec('SELECT * FROM branches;').to_a # => [{"name"=>"trunk", "commit_id"=>"1", "created_at"=>"2017-10-06 20:39:01.796488", "creator_id"=>"1"}]

# A lib so that I can have some abstractions
class PgGit
  def initialize(db, user_id)
    self.db = db
    set_user user_id
  end

  def schemas
    all <<-SQL
      SELECT schema_name
      FROM information_schema.schemata
      WHERE schema_name like 'branch_%'
    SQL
  end

  def branches
    all 'SELECT * FROM branches;'
  end

  def branch
    first 'SELECT * FROM branches WHERE name = $1', user.branch_name
  end

  def create_branch(name)
    execute <<-SQL, name, branch.commit_id, user.id
      INSERT INTO branches (name, commit_id, creator_id)
      VALUES ($1, $2, $3);
    SQL
    execute "CREATE SCHEMA branch_#{name};" # FIXME: SQL injection
  end

  def switch_branch(name)
    execute 'UPDATE users SET branch_name = $1 WHERE id = $2', name, user.id
    set_user user.id
  end

  def commit
    first 'SELECT * FROM commits WHERE id = $1', branch.commit_id
  end

  def tables
    # lineage()
  end

  def create_table(name, columns)
    # make sure we're on an open commit
    commit = commit()
    if commit.committed_at
      execute 'INSERT INTO commits (author_id) VALUES ($1)', user.id
      commit = first('SELECT * FROM commits ORDER BY created_at DESC LIMIT 1')
      execute 'UPDATE branches SET commit_id = $1 WHERE name = $2', commit.id, branch.name
    end

    # create the table
    table_delta = first <<~SQL, 'create', name
      INSERT INTO deltas_for_tables (type, table_name)
      VALUES ($1, $2)
      RETURNING *;
    SQL

    execute 'INSERT INTO deltas (type, commit_id, delta_id) VALUES ($1, $2, $3)',
            'table', commit.id, table_delta.id

    # create the columns
    columns.each do |column_name, column_type|
      column_delta = first <<~SQL, 'create', name, column_name, column_type
        INSERT INTO deltas_for_columns (type, table_name, column_name, column_type)
        VALUES ($1, $2, $3, $4)
        RETURNING *;
      SQL

      execute 'INSERT INTO deltas (type, commit_id, delta_id) VALUES ($1, $2, $3)',
              'column', commit.id, column_delta.id
    end

    # FIXME: NEXT UP:
    # QUERY THE DATA BACK OUT AND THEN CREATE IT IN THE SCHEMA!!
  end

  private

  attr_accessor :db, :user

  def first(sql, *variables)
    all(sql, *variables).first
  end

  def all(sql, *variables)
    execute(sql, *variables).map { |hash| Result.new hash }
  end

  def execute(sql, *variables)
    db.exec_params(sql, variables)
  end

  def set_user(id)
    self.user = first 'SELECT * FROM users WHERE id = $1', id
  end


  class Result
    def initialize(result_hash)
      @hash = result_hash.map { |k, v| [k.intern, v] }.to_h
    end
    def respond_to_missing(name)
      @hash.key? name
    end
    def method_missing(name)
      return @hash.fetch name if @hash.key? name
      super
    end
    def inspect
      PP.pp(self, '')
    end
    def pretty_print(pp)
      pp.group 2, "#<Result", '>' do
        @hash.each.with_index do |(k, v), i|
          pp.breakable ' '
          pp.text "#{k}=#{v.inspect}"
        end
      end
    end
  end
end




# =====  Testing it out  =====
pggit = PgGit.new db, system_user['id']

# make a branch
pggit.schemas.map(&:schema_name) # => []
pggit.branches.map(&:name)       # => ["trunk"]
pggit.create_branch 'first_changes'
pggit.schemas.map(&:schema_name) # => ["branch_first_changes"]
pggit.branches.map(&:name)       # => ["trunk", "first_changes"]

# switch to the branch
pggit.branch                     # => #<Result\n  name="trunk"\n  commit_id="1"\n  created_at="2017-10-06 20:39:01.796488"\n  creator_id="1">\n
pggit.switch_branch 'first_changes'
pggit.branch                     # => #<Result\n  name="first_changes"\n  commit_id="1"\n  created_at="2017-10-06 20:39:01.801439"\n  creator_id="1">\n

# create the table
pggit.tables # => nil
pggit.commit # => #<Result\n  id="1"\n  author_id="1"\n  description="Root Commit"\n  details="The parent commit that all future commits will be based off of"\n  created_at="2017-10-06 20:39:01.795668"\n  committed_at="2017-10-06 20:39:01.795668">\n
pggit.create_table 'users', name: 'varchar', is_admin: 'boolean'
pggit.tables # => nil
pggit.commit # => #<Result\n  id="2"\n  author_id="1"\n  description=""\n  details=""\n  created_at="2017-10-06 20:39:01.807536"\n  committed_at=nil>\n
pggit.commit! description: 'Create users table', details: "so we have somethign to play with" # ~> NoMethodError: undefined method `commit!' for #<PgGit:0x007fa0108c5278>\nDid you mean?  commit
pggit.commit # =>

pggit.commit # =>
pggit.tables # =>
pggit.switch_branch 'root'
pggit.commit # =>
pggit.tables # =>

# ~> NoMethodError
# ~> undefined method `commit!' for #<PgGit:0x007fa0108c5278>
# ~> Did you mean?  commit
# ~>
# ~> /Users/xjxc322/gamut/pg_version_control_experiment/experiments/implementation.rb:300:in `<main>'
