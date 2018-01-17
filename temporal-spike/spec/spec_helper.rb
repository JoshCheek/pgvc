require 'pg'
require 'awesome_print'


module SpecHelpers
  class << self
    attr_accessor :db
  end


  dbname = ENV.fetch 'db', 'pgvc_temporal_test'
  # PG.connect(dbname: 'postgres').exec("drop database #{dbname}")
  # PG.connect(dbname: 'postgres').exec("create database #{dbname}")
  self.db = PG.connect(dbname: dbname)

  def db
    SpecHelpers.db
  end

  def show_view(db)
    cats  = db.exec('select * from test1.categories').to_a
    prods = db.exec('select * from test1.products').to_a
    ap categories: cats, products: prods
  end

  def show_versions(db)
    cats  = db.exec('select * from test1_versions.categories').to_a
    prods = db.exec('select * from test1_versions.products').to_a
    ap categories: cats, products: prods
  end

  def insert(db, tables)
    sql = ''
    tables.each do |table, records|
      records.map do |record|
        sql << "insert into test1.#{table} (#{record.keys.join(',')}) values (#{record.values.join(',')});"
      end
    end
    db.exec sql
  end


  def update(db, tables)
    sql = ''
    tables.each do |table, updates|
      updates.map do |update|
        update = update.dup
        id = update.delete :id
        update_sql = update.map { |k, v| "#{k} = #{v}" }.join(" ")
        sql << "update test1.#{table} set #{update_sql} where id = #{id};"
      end
    end
    db.exec sql
  end


  def delete(db, tables)
    sql = ''
    tables.each do |table, ids|
      sql << "delete from test1.#{table} where id in (#{ids.join(", ")});"
    end
    db.exec sql
  end

  def now(db)
    db.exec('select current_timestamp')[0].values.first
  end

  def assert_rows(db, table_assertions)
    table_assertions.each do |table, row_assertions|
      actual_rows = db.exec("select * from test1.#{table}").map(&:to_h)
      expected_rows = row_assertions.map do |row_assertion|
        row_assertion.map { |k, v| [k.to_s, v.to_s] }.to_h
      end
      actual_rows.sort_by! { |row| row['id'].to_i }
      expected_rows.sort_by! { |row| row['id'].to_i }
      expect(actual_rows).to eq expected_rows
    end
  end

  def sql_library_code
    File.read(File.expand_path '../lib/pgvc_temporal.pls', __dir__)
  end
end

# db setup
RSpec.configure do |config|
  config.include SpecHelpers
end
