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
    set search_path = public;
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
require 'pgvc/git'


class App < Sinatra::Base
  enable :sessions

  before { @username = session['username'] }
  attr_reader :username, :branch, :git
  alias logged_in? username

  def call(env)
    ActiveRecord::Base.connection_pool.with_connection do |ar_conn|
      pg_conn  = ar_conn.raw_connection
      username = env['rack.session']['username'] || 'anonymous'
      env['pgvc.pg_connection'] = pg_conn
      @git = Pgvc::Git.new(pg_conn)
      git.config_user_ref(username)
      @branch = git.branch.find(&:current?)
      begin
        super(env)
      ensure
        git.exec 'set search_path = public;' # FIXME: dumb hack
      end
    end
  end

  def pg_connection
    env.fetch 'pgvc.pg_connection'
  end

  def pgvc
    @pgvc ||= Pgvc.new pg_connection
  end



  get '/reset' do
    pg_connection.exec 'select * from reset_db()'
    Pgvc.init pg_connection, default_branch: 'publish'
    redirect '/'
  end

  # see all branches
  get '/branches' do
    redirect '/' unless logged_in?
    @branches = git.branch
    erb :branches
  end

  # create a new branch
  post '/branches' do
    redirect '/' unless logged_in? # not actually tested
    git.branch params['new_branch_name']
    @branches = git.branch
    erb :branches
  end

  # # delete a branch
  # delete '/branches'

  # # checkout a branch
  # post '/branch'

  # display the products
  get '/' do
    @products = Product.all
    erb :root
  end

  # login
  post '/session' do
    session['username'] = params['username']
    redirect '/'
  end

  # # logout
  # delete '/session'
end
