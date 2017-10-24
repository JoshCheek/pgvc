require 'pgvc'

class Pgvc::Git
  def initialize(connection)
    @connection = connection
    @client = Pgvc.new connection
  end

  def config_user_ref(name)
    fn 'config_user_ref', name
  end

  def init
    fn 'init'
  end

  def add_table(table_name)
    fn 'add_table', table_name
  end

  def commit(message)
    fn 'commit', message
  end

  def log
    fn 'log'
  end

  def branch
    fn 'branch'
  end

  def fn(name, *args)
    placeholders = args.map.with_index(1) { |_, i| "$#{i}" }.join(", ")
    fn_call      = "git.#{name}(#{placeholders})"
    connection.exec_params("select * from #{fn_call};", args).map { |r| Pgvc::Record.new r }
  end

  def fn1(*args, &block)
    fn(*args, &block).first
  end

  private

  attr_reader :client, :connection
end
