require 'pg'
require 'pgvc/record'

class Pgvc
  SQL_PATH = File.expand_path 'pgvc', __dir__

  def self.exec_sql(db, filename)
    path = File.join SQL_PATH, filename
    path = "#{path}.sql" unless path.end_with? '.sql'
    db.exec File.read(path)
  end


  # track: array of names of the tables to track in version control
  def self.bootstrap(db, track:[], system_userid:, default_branch:)
    exec_sql db, 'create_tables'
    exec_sql db, 'create_functions'

    client = new(db)
    client.call_fn 'initialize', system_userid, default_branch
    track.each { |table_name| client.track_table table_name }
    client
  end
end


class Pgvc
  def initialize(connection)
    self.connection = connection
  end

  def get_branch(user_id)
    call_fn('get_branch', user_id, composite: true).first
  end

  def switch_branch(user_id, branch_name)
    call_fn('switch_branch', user_id, branch_name).first
  end

  def get_branches
    call_fn 'get_branches'
  end

  def rename_branch(old, new)
    call_fn('rename_branch', old, new, composite: true).first
  end

  def get_commit(hash)
    call_fn('get_commit', hash, composite: true).first
  end

  def create_commit(summary:, description:, user_id:, created_at:)
    call_fn('create_commit', summary, description, user_id, created_at, composite: true).first
  end

  def get_parents(commit_hash)
    call_fn 'get_parents', commit_hash
  end

  def create_branch_from_current(name, user_id)
    call_fn('create_branch_from_current', name, user_id, composite: true).first
  end

  def delete_branch(name)
    call_fn('delete_branch', name).first
  end

  def track_table(name)
    call_fn 'track_table', name
  end

  def call_fn(name, *args, composite: false)
    placeholders = args.map.with_index(1) { |_, i| "$#{i}" }.join(", ")
    fn_call      = "vc.#{name}(#{placeholders})"
    connection.exec_params("select * from #{fn_call};", args).map { |r| Record.new r }
  end

  private

  attr_accessor :connection
end

