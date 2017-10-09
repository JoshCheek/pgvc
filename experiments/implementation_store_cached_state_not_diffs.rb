# A branch is a pointer to a commit
# A commit is a hashed database, author, commit message, and date
# A database is a hashed list of tables
# A table is a name, hashed structure and list of rows (or row sets as an optimization detail?)
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


# =====  Reset and connect to the database  =====
require 'pg'
db = PG.connect(dbname: 'postgres')
db.exec("DROP DATABASE IF EXISTS pg_git;")
db.exec("CREATE DATABASE pg_git;")
db = PG.connect dbname: 'pg_git'

# =====  The tables  =====
hash = "varchar(32)" # size of md5
db.exec <<-SQL
  create type pg_git_type as enum (
    'database',
    'table'
  );
  create table pg_git_objects (
    hash #{hash} primary key,
    type pg_git_type
  );
  create table pg_git_object_databases (
    hash #{hash} primary key
  );
  create table pg_git_object_database_tables (
    database_hash #{hash},
    table_hash    #{hash}
  );
  create table pg_git_object_tables (
    hash #{hash} primary key,
    name varchar
  );
  -- Commit: a group of changes (deltas)
  create table commits (
    id            serial primary key,
    author_id     int,
    description   varchar default '',
    details       text default '',
    created_at    timestamp default now(),
    committed_at  timestamp,
    database_hash #{hash}
  );
  -- Ancestry: relationship between commits
  create table ancestry (
    parent_id int,
    child_id  int
  );
  -- Branch: a name for a commit
  -- these will be used to track which commits we are interested in viewing and editing
  -- eg branches will be cached, where commits won't, because there would be too many of them
  create table branches (
    id         serial primary key,
    name       varchar,
    commit_id  int,
    created_at timestamp default now(),
    creator_id int -- a user
  );
  create table users (
    id        serial primary key,
    username  varchar,
    branch_id int default 1 -- 1 is the id of the primary branch
  );
SQL

# functions
db.exec <<-SQL
  create or replace function set_user(integer)
  returns integer as $$
    select set_config('pg_git.current_user_id', $1::varchar, true)::integer;
  $$ language sql;

  create or replace function get_user_id()
  returns integer as $$
    select current_setting('pg_git.current_user_id')::integer;
  $$ language sql;

  create or replace function get_user()
  returns users as $$
    select * from users where id = get_user_id() limit 1;
  $$ language sql;

  create or replace function get_branch(out branch branches)
  returns branches as $$
  begin
    select *
    from branches
    join get_user() on (branches.id = branch_id)
    into branch
    limit 1;
  end
  $$ language plpgsql;

  create or replace function get_branch_id()
  returns integer as $$
    select id from get_branch();
  $$ language sql;

  create or replace function initial_setup()
  returns record as $$
  declare
    myuser users;
    mycommit commits;
  begin
    -- create the system user --
    insert into users (username)
      values ('system')
      returning * into myuser;
    perform set_user(myuser.id);

    -- create the commit --
    insert into commits (author_id, description, details, committed_at, database_hash)
      values (get_user_id(), 'Initial commit', 'Initial commit', now(), '--------------------------------')
      returning * into mycommit;

    -- create the branch --
    insert into branches (name, commit_id, creator_id)
      values ('primary', mycommit.id, get_user_id());

    -- select current_setting('pg_git.current_user_id') into userid;
    -- return get_user_id();
    return get_branch();
  end
  $$ language plpgsql;
SQL



(db.exec "select table_name from information_schema.tables where table_schema = 'public'").to_a
# => [{"table_name"=>"pg_git_objects"},
#     {"table_name"=>"pg_git_object_databases"},
#     {"table_name"=>"pg_git_object_database_tables"},
#     {"table_name"=>"pg_git_object_tables"},
#     {"table_name"=>"commits"},
#     {"table_name"=>"ancestry"},
#     {"table_name"=>"branches"},
#     {"table_name"=>"users"}]


# db.exec('select set_user(1);').to_a # => [{"set_user"=>"1"}]
db.exec('select initial_setup();').to_a # => [{"initial_setup"=>"(1,primary,1,\"2017-10-09 14:58:37.939846\",1)"}]
db.exec('select * from users;').to_a    # => [{"id"=>"1", "username"=>"system", "branch_id"=>"1"}]
db.exec('select * from branches;').to_a # => [{"id"=>"1", "name"=>"primary", "commit_id"=>"1", "created_at"=>"2017-10-09 14:58:37.939846", "creator_id"=>"1"}]
db.exec('select * from ancestry;').to_a # => []
db.exec('select * from commits;').to_a  # => [{"id"=>"1", "author_id"=>"1", "description"=>"Initial commit", "details"=>"Initial commit", "created_at"=>"2017-10-09 14:58:37.939846", "committed_at"=>"2017-10-09 14:58:37.939846", "database_hash"=>"--------------------------------"}]
db.exec('select * from pg_git_objects').to_a
# => []

__END__
# =====  Initial version control data  =====
# system user
system_user = db.exec_params(<<-SQL, ['system']).first
  INSERT INTO users (username) VALUES ($1) RETURNING *;
SQL

# empty database
empty_database = db.exec_params(
 'INSERT INTO pg_git_object_databases (hash) VALUES ($1) returning *;',
 [hash('database')]
)

# root commit
root_commit = db.exec_params(
  'INSERT INTO commits (author_id, description, details, committed_at, database_hash) VALUES ($1, $2, $3, now()) RETURNING *;',
  [ system_user['id'],
    'Root Commit',
    'The parent commit that all future commits will be based off of',
    'now()',
    empty_database['hash'],
  ]
).first

# trunk branch
trunk_branch = db.exec_params(
  'INSERT INTO branches (name, commit_id, creator_id) VALUES ($1, $2, $3) RETURNING *',
  ['trunk', root_commit['id'], system_user['id']]
).first

# the system user is on the trunk branch
system_user = db.exec(<<-SQL, [trunk_branch['name'], system_user['id']]).first # ~> PG::UndefinedColumn: ERROR:  column "branch_name" of relation "users" does not exist\nLINE 1:   UPDATE users SET branch_name = $1 WHERE id = $2 RETURNING ...\n                           ^\n
  UPDATE users SET branch_name = $1 WHERE id = $2 RETURNING *;
SQL

db.exec('SELECT * FROM users;').to_a # =>
db.exec('SELECT * FROM commits;').to_a # =>
db.exec('SELECT * FROM branches;').to_a # =>

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
pggit.schemas.map(&:schema_name) # =>
pggit.branches.map(&:name)       # =>
pggit.create_branch 'first_changes'
pggit.schemas.map(&:schema_name) # =>
pggit.branches.map(&:name)       # =>

# switch to the branch
pggit.branch                     # =>
pggit.switch_branch 'first_changes'
pggit.branch                     # =>

# create the table
pggit.tables # =>
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

# ~> PG::UndefinedColumn
# ~> ERROR:  column "branch_name" of relation "users" does not exist
# ~> LINE 1:   UPDATE users SET branch_name = $1 WHERE id = $2 RETURNING ...
# ~>                            ^
# ~>
# ~> /Users/xjxc322/gamut/pg_version_control_experiment/experiments/implementation_store_cached_state_not_diffs.rb:109:in `exec'
# ~> /Users/xjxc322/gamut/pg_version_control_experiment/experiments/implementation_store_cached_state_not_diffs.rb:109:in `<main>'
