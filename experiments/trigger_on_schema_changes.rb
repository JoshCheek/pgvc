require 'pg'

db = PG.connect(dbname: 'josh_testing')
db.exec 'begin' # discard changes

def db.exec(*)
  super.to_a
end

db.exec <<~SQL
  create table users (
    id         serial,
    first_name varchar,
    last_name  varchar
  );

  create or replace function log_ddl_info() returns event_trigger as $$
  begin
    -- Looks like these are the only variables they define:
    -- https://github.com/postgres/postgres/blob/f987f83de20afe3ba78be1e15db5dffe7488faa7/src/pl/plpgsql/src/pl_comp.c#L687-L715
    -- https://github.com/postgres/postgres/blob/f987f83de20afe3ba78be1e15db5dffe7488faa7/src/pl/plpgsql/src/pl_exec.c#L917-L924
    raise warning 'TG_EVENT: %', TG_EVENT;
    raise warning 'TG_TAG:   %', TG_TAG;
  end $$ language plpgsql;

  create event trigger log_ddl_info_trigger on ddl_command_start
    execute procedure log_ddl_info();

  -- What we would like to do is see this entire query from the trigger, so that
  -- we can run it against the other schemas
  alter table users rename first_name to first;
  SQL

# !> WARNING:  TG_EVENT: ddl_command_start
# !> WARNING:  TG_TAG:   ALTER TABLE
