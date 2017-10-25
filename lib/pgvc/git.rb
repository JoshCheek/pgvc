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
    fn1 'commit', message
  end

  def log
    fn 'log'
  end

  def branch(*args)
    fn 'branch', *args
  end

  def checkout(branch_name)
    fn 'checkout', branch_name
  end

  def diff(*args)
    fn 'diff', *args
  end

  def fn(name, *args)
    placeholders = args.map.with_index(1) { |_, i| "$#{i}" }.join(", ")
    fn_call      = "git.#{name}(#{placeholders})"
    exec_params "select * from #{fn_call};", args
  end

  def fn1(*args, &block)
    fn(*args, &block).first
  end

  def exec(sql)
    connection.exec(sql).map { |r| Pgvc::Record.new r }
  end

  def exec_params(sql, params)
    connection.exec_params(sql, params).map { |r| Pgvc::Record.new r }
  end

  private

  attr_reader :client, :connection
end
