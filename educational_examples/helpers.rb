require 'pg'

# Reset the database
PG.connect(dbname: 'postgres')
  .tap { |db| db.exec "DROP DATABASE IF EXISTS pg_git;" }
  .tap { |db| db.exec "CREATE DATABASE pg_git;" }

$db = PG.connect dbname: 'pg_git'
def db
  $db
end

# A convenience method to wrap database calls
def sql(sql, *params, db: $db)
  # the rules are different when you do / don't have params
  # so use the normal `exec`, when possible
  if params.empty?
    db.exec sql
  else
    db.exec_params sql, params
  end.map { |row| Record.new row }
end

# A convenience wrapper so you can call sql by wrapping a heredoc in backticks
alias ` sql


# Wraps a database record result (hash of strings) in a convenience class
class Record
  def initialize(result_hash)
    @hash = result_hash.map { |k, v| [k.intern, v] }.to_h
  end
  def to_h
    @hash.dup
  end
  def ==(other)
    to_h == other.to_h
  end
  def respond_to_missing(name)
    @hash.key? name
  end
  def method_missing(name, *)
    return @hash.fetch name if @hash.key? name
    super
  end
  def [](key)
    @hash[key.intern]
  end
  def inspect
    ::PP.pp(self, '').chomp
  end
  def pretty_print(pp)
    pp.group 2, "#<Record", '>' do
      @hash.each.with_index do |(k, v), i|
        pp.breakable ' '
        pp.text "#{k}=#{v.inspect}"
      end
    end
  end
end


# Some assertions for verifying its behaviour without having to check output
module Assertions
  def assert!(bool, message="failed assertion")
    fail_assertion message unless bool
    bool
  end

  alias_method :eq!, def assert_equal(e, a, message=nil)
    return a if e == a
    fail_assertion "#{message&&message+"\n\n"}Expected #{e.inspect}\nTo Equal #{a.inspect}"
  end

  alias_method :ne!, def refute_equal(ne, a, message=nil)
    return a unless ne == a
    fail_assertion "#{message&&message+"\n\n"}Expected      #{a.inspect}\nTo *NOT* Equal #{ne.inspect}"
  end

  private def fail_assertion(message)
    err = RuntimeError.new message
    err.set_backtrace caller.drop(1)
    raise err
  end
end


# make them available to the main object
extend Assertions
