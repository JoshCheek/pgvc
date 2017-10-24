DBNAME = 'pgvc_testing'.freeze
begin
  ROOT_DB = PG.connect dbname: DBNAME
rescue PG::ConnectionBad
  PG.connect(dbname: 'postgres'.freeze)
    .exec("create database #{DBNAME};")
  retry
end

ROOT_DB.exec <<~SQL
  SET client_min_messages=WARNING;

  create or replace function reset_test_db() returns void as $$
    declare name varchar;
    begin
      for name in
        select schema_name from information_schema.schemata
      loop
        if name like 'branch_%' then
          execute format('drop schema %s cascade', quote_ident(name));
        end if;
      end loop;
      drop schema if exists vc cascade;
      drop schema if exists git cascade;
      drop table if exists users;
      drop table if exists products;
    end $$ language plpgsql;
SQL


module SpecHelper
  module Acceptance
    def self.included(klass)
      klass.class_eval do
        before { ROOT_DB.exec 'select reset_test_db()' }

        before do
          @db = PG.connect dbname: DBNAME
          db.exec <<~SQL
            SET client_min_messages=WARNING;

            create table users (
              id serial primary key,
              name varchar
            );
            insert into users (name) values ('system'), ('josh');

            create table products (
              id serial primary key,
              name varchar,
              colour varchar
            );
          SQL
          @user, @system_user = sql "select * from users;"
        end
      end
    end

    attr_reader :db, :user, :system_user

    def sql1(sql, *params, **options)
      sql(sql, *params, **options).first
    end

    def sql(sql, *params, db: get_db(user))
      if params.empty?
        db.exec sql # prefer exec as it is more permissive
      else
        db.exec_params sql, params
      end.map { |row| Pgvc::Record.new row }
    end

    def get_db(user)
      return self.db unless user && client
      branch = client.user_get_branch user.id
      client.connection_for(branch.name)
    end

    def insert_products(products, client: self.client)
      products.each do |key, value|
        sql 'insert into products (name, colour) values ($1, $2)', key, value
      end
    end

    def assert_products(assertions, client: self.client)
      results = sql('select * from products')
      assertions.each do |key, values|
        expect(pluck results, key).to eq values
      end
    end

    def pluck(records, key)
      records.map { |record| record[key] }
    end
  end
end
