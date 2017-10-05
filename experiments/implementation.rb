require 'pg'

# Reset the database
lambda do
  db = PG.connect dbname: 'postgres'
  db.exec("DROP DATABASE IF EXISTS pg_git;")
  db.exec("CREATE DATABASE pg_git;")
end[]

db = PG.connect dbname: 'pg_git'

# User: Someone using the system
db.exec <<-SQL
  CREATE TABLE users (
    id serial primary key,
    username varchar,
    branch_name varchar
  );
SQL

# Commit: a group of changes (deltas)
db.exec <<-SQL
  CREATE TABLE commits (
    id serial primary key,
    author_id int,
    description varchar,
    details text
    -- created_at timestamp,
    -- committed_at timestamp,
  );
SQL

# Ancestry: relationship between commits
db.exec <<-SQL
  CREATE TABLE ancestry (
    parent_id int,
    child_id  int
  );
SQL

# Branch: a name for a commit
# these will be used to track which commits we are interested in viewing and editing
# eg branches will be cached, where commits won't, because there would be too many of them
db.exec <<-SQL
  CREATE TABLE branches (
    name varchar primary key,
    commit_id int,
    -- created_at timestamp,
    creator_id int -- a user
  );
SQL

# Delta: a change to the data
db.exec <<-SQL
  CREATE TYPE delta_type AS ENUM (
    'delete_table',
    'create_table',
    'drop_column',
    'add_column',
    'delete_row',
    'insert_row',
    'modify_cell'
  );
  CREATE TABLE deltas (
    commit_id int,
    table_name varchar,
    column_name varchar,
    row_id integer,
    type delta_type
  )
SQL


# Query the hierarchy out of the ancestors
def lineage(db, commit_id)
  db.exec_params <<-SQL, [commit_id]
    WITH
      RECURSIVE ancestors (depth, id) AS (
        SELECT 0::integer, $1::integer

        UNION ALL

        SELECT prev.depth+1, crnt.parent_id
        FROM ancestors prev
        JOIN ancestry  crnt ON (prev.id = crnt.child_id)
      ),

      unique_ancestors (depth, id) AS (
        SELECT min(depth), id
        FROM ancestors
        GROUP BY id
      )

    SELECT depth, chars.*
    FROM unique_ancestors a
    JOIN chars ON (chars.id = a.id)
    ORDER BY a.depth; -- add DESC to get the path from the root to the node in question
  SQL
end


# Initial version control data
# system user
db.exec_params 'INSERT INTO users (username) VALUES ($1);', ['system']
system_user = db.exec('SELECT * FROM users;').first

# root commit
db.exec_params 'INSERT INTO commits (author_id, description, details) VALUES ($1, $2, $3);', [
  system_user['id'], 'Root Commit', 'The parent commit that all future commits will be based off of'
]
root_commit = db.exec_params('SELECT * from commits;').first

# trunk branch
db.exec_params 'INSERT INTO branches (name, commit_id, creator_id) VALUES ($1, $2, $3)', [
  'trunk', root_commit['id'], system_user['id']
]
trunk_branch = db.exec('SELECT * FROM branches;').first
# => {"name"=>"trunk", "commit_id"=>"1", "creator_id"=>"1"}

# the system user is on the trunk branch
db.exec 'UPDATE users SET branch_name = $1 WHERE id = $2', [
  trunk_branch['name'], # => "trunk"
  system_user['id']     # => "1"
]
system_user = db.exec('SELECT * FROM users;').first
db.exec('SELECT * FROM users;').to_a # => [{"id"=>"1", "username"=>"system", "branch_name"=>"trunk"}]
db.exec('SELECT * FROM commits;').to_a # => [{"id"=>"1", "author_id"=>"1", "description"=>"Root Commit", "details"=>"The parent commit that all future commits will be based off of"}]
db.exec('SELECT * FROM branches;').to_a # => [{"name"=>"trunk", "commit_id"=>"1", "creator_id"=>"1"}]

# A lib so that I can have some abstractions
class PgGit
  def initialize(db, user_id)
    self.db   = db
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

  private

  attr_accessor :db, :user

  def first(sql, *variables)
    all(sql, *variables).first
  end

  def all(sql, *variables)
    execute(sql, *variables).map { |hash| Result.new hash }
  end

  def execute(sql, *variables)
    # sql %= variables.keys.map.with_index(1) { |var, i| [var, "$#{i}"] }.to_h # ~> ArgumentError: malformed format string - %'
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
      "#<Result#{@hash.inspect}>"
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
pggit.branch                     # => #<Result{:name=>"trunk", :commit_id=>"1", :creator_id=>"1"}>
pggit.switch_branch 'first_changes'
pggit.branch                     # => #<Result{:name=>"first_changes", :commit_id=>"1", :creator_id=>"1"}>

# create the table
pggit.tables # => NoMethodError: undefined method `tables' for #<PgGit:0x007fe4c503f820>
pggit.commit # =>
pggit.create_table 'users', name: 'varchar', is_admin: 'boolean'
pggit.tables # =>
pggit.commit # =>
pggit.commit! description: 'Create users table', details: "so we have somethign to play with"
pggit.commit # =>

pggit.commit # =>
pggit.tables # =>
pggit.switch_branch 'root'
pggit.commit # =>
pggit.tables # =>

# ~> NoMethodError
# ~> undefined method `tables' for #<PgGit:0x007fe4c503f820>
# ~>
# ~> /Users/xjxc322/gamut/pg_version_control_experiment/experiments/implementation.rb:223:in `<main>'
