require 'pg'
require 'pgvc/record'

class Pgvc
  SQL_PATH = File.expand_path 'pgvc', __dir__

  def self.file(filename)
    File.read File.join(SQL_PATH, filename)
  end

  def self.init(db, system_user_ref:, default_branch:)
    db.exec file('tables.sql')
    db.exec file('private_functions.sql')
    db.exec file('public_functions.sql')
    new(db).tap { |pgvc| pgvc.fn 'init', system_user_ref.to_s, default_branch }
  end
end


require 'pg'
class Pgvc
  def initialize(db)
    self.connection = db
    self.branch_connections = {}
  end

  def get_branch(user_ref)
    fn1 'get_branch', user_ref.to_s
  end

  def switch_branch(user_ref, branch_name)
    fn1 'switch_branch', user_ref.to_s, branch_name
  end

  def get_branches
    fn 'get_branches'
  end

  def rename_branch(old, new)
    fn1 'rename_branch', old, new
  end

  def get_commit(hash)
    fn1 'get_commit', hash
  end

  def create_commit(summary:, user_ref:, description:'', created_at:Time.now)
    fn1 'create_commit', summary, description, user_ref.to_s, created_at
  end

  def get_parents(commit_hash)
    fn 'get_parents', commit_hash
  end

  def create_branch_from_current(name, user_ref)
    fn1 'create_branch_from_current', name, user_ref.to_s
  end

  def delete_branch(name)
    fn1 'delete_branch', name
  end

  def track_table(name)
    fn 'track_table', name
  end

  def fn(name, *args)
    placeholders = args.map.with_index(1) { |_, i| "$#{i}" }.join(", ")
    fn_call      = "vc.#{name}(#{placeholders})"
    connection.exec_params("select * from #{fn_call};", args).map { |r| Record.new r }
  end

  def fn1(*args, &block)
    fn(*args, &block).first
  end

  def connection_for(branch_name)
    branch_connections.fetch branch_name do
      branch_connections[branch_name] = build_connection_for branch_name
    end
  end

  private

  attr_accessor :connection, :branch_connections

  def dbname
    connection.conninfo_hash.fetch :dbname
  end

  def build_connection_for(branch_name)
    conn     = PG.connect dbname: dbname
    branches = conn.exec_params('select * from vc.branches where name = $1', [branch_name])
    branch   = Record.new branches.first
    conn.exec_params "set search_path = #{branch.schema_name}, public;"
    conn
  end
end

