require 'pg'

class Pgvc
  def self.bootstrap(db, track:[], system_userid:)
    db.exec <<~SQL
    create extension if not exists hstore;

    create schema vc;
    set search_path = vc;

    create table tracked_tables (
      name varchar unique
    );

    create table tables (
      vc_hash    character(32),
      row_hashes character(32)[]
    );

    create table rows (
      vc_hash character(32),
      data    public.hstore
    );

    create table user_branches (
      user_id   integer primary key,
      branch_id integer,
      is_system boolean
    );
    SQL

    db.exec <<~SQL
      create function set_system_user_id(in id integer) returns void as $$
      begin
        update user_branches set is_system = false;
        insert into user_branches (user_id, branch_id, is_system)
          values (id, 1, true)
          on conflict (user_id) do update
          set is_system = EXCLUDED.is_system;
      end $$ language plpgsql set search_path = vc;


      create function track_table(in tblname varchar) returns void as $$
      begin
        insert into tracked_tables (name) values (tblname)
          on conflict do nothing;

        -- FIXME: Here is where we should add the trigger to the table
      end $$ language plpgsql set search_path = vc;
    SQL

    db.exec 'set search_path = public;'

    client = new(db)
    client.fn 'set_system_user_id', system_userid
    track.each { |table_name| client.track_table table_name }
  end
end

class Pgvc
  def initialize(connection)
    self.connection = connection
  end

  def create_branch(name)
    fn 'create_branch', name
  end

  def track_table(name)
    fn 'track_table', name
  end


  def fn(name, *args)
    placeholders = args.map.with_index(1) { |_, i| "$#{i}" }.join(", ")
    connection.exec_params "select vc.#{name}(#{placeholders});", args
  end
    # insert insert vc.tracked_tables (name) values ($1);
  private

  attr_accessor :connection
end
