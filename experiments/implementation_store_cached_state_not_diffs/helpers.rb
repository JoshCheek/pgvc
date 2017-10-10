require 'pg'
require_relative 'result'

class Database
  def initialize(db_name, reset: false)
    self.db_name = db_name
    reset() if reset
  end

  def reset
    PG.connect(dbname: 'postgres')
      .tap { |db| exec "DROP DATABASE IF EXISTS \"#{db_name}\";", db: db }
      .tap { |db| exec "CREATE DATABASE \"#{db_name}\";", db: db }
    db.exec file 'structure.sql'
    db.exec file 'seed.sql'
    db.exec file 'functions.sql'
    self
  end

  def first(sql, *variables, **options)
    hash = exec(sql, *variables, **options).first
    Result.new hash
  end

  def all(sql, *variables, **options)
    exec(sql, *variables, **options).map { |hash| Result.new hash }
  end

  def exec(sql, *variables, db: db())
    db.exec_params sql, variables
  end

  private

  ROOT_DIR = File.realdirpath __dir__

  attr_accessor :db_name


  def db
    @db ||= PG.connect dbname: db_name
  end

  def file(filename)
    File.read File.expand_path(filename, ROOT_DIR)
  end
end
