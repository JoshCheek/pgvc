ENV['RACK_ENV'] ||= 'development'

require 'sinatra/base'
require 'active_record'
ActiveRecord::Base.establish_connection adapter: 'postgresql', database: 'pgvc_example'
ActiveRecord::Base.logger = Logger.new $stdout unless ENV['RACK_ENV'] == 'test'

ActiveRecord::Base.connection.execute <<~SQL
SET client_min_messages=WARNING;
create or replace function reset_db() returns void as $$
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
    create table products (
      id serial,
      name text,
      colour text
    );
  end $$ language plpgsql;
end
SQL

class Product < ActiveRecord::Base
end



$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'pgvc'


class App < Sinatra::Base
  get '/reset' do
    ActiveRecord::Base.connection.execute 'select * from reset_db()'
    Pgvc.init ActiveRecord::Base.connection.raw_connection, default_branch: 'publish'
  end

  # # see all branches
  # get '/branches'

  # # create a new branch
  # post '/branches'

  # # delete a branch
  # delete '/branches'

  # # checkout a branch
  # post '/branch'

  # # display the products
  # get '/'

  # # login
  # post '/session'

  # # logout
  # delete '/session'
end
