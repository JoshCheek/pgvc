require 'pg'

class Pgvc
  SQL_PATH = File.expand_path 'pgvc', __dir__

  def self.exec_sql(db, filename)
    path = File.join(SQL_PATH, filename)
    path = "#{path}.sql" unless path.end_with? '.sql'
    db.exec File.read(path)
  end


  def self.bootstrap(db, track:[], system_userid:)
    exec_sql db, 'create_tables'
    exec_sql db, 'create_functions'

    client = new(db)
    client.call_fn 'set_system_user_id', system_userid
    track.each { |table_name| client.track_table table_name }
  end
end

class Pgvc
  def initialize(connection)
    self.connection = connection
  end

  def create_branch(name)
    call_fn 'create_branch', name
  end

  def track_table(name)
    call_fn 'track_table', name
  end

  def call_fn(name, *args)
    placeholders = args.map.with_index(1) { |_, i| "$#{i}" }.join(", ")
    connection.exec_params "select vc.#{name}(#{placeholders});", args
  end
    # insert insert vc.tracked_tables (name) values ($1);
  private

  attr_accessor :connection
end
