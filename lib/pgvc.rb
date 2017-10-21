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

  def get_commit(hash)
    call_fn('get_commit', hash, composite: true).first
  end

  # def create_branch(name, user.id)
  #   call_fn 'create_branch', name
  # end

  def track_table(name)
    call_fn 'track_table', name
  end

  def call_fn(name, *args, composite: false)
    placeholders = args.map.with_index(1) { |_, i| "$#{i}" }.join(", ")
    fn_call      = "vc.#{name}(#{placeholders})"
    fn_call      = "(#{fn_call}).*" if composite
    connection.exec_params("select #{fn_call};", args)
              .map { |row| Record.new row }
  end

  private

  attr_accessor :connection
end

