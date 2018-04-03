create schema if not exists pgvc_temporal;

-- functions to manage the current time, the time we are viewing the DB from
create or replace function
  pgvc_temporal.timetravel_to(text) returns text as $$
  begin
    perform set_config('pgvc_temporal.timetravel_time', $1, false);
    return $1;
  end $$ language plpgsql;

create or replace function
  pgvc_temporal.timetravel_time() returns timestamp as $$
  select coalesce(
    current_setting('pgvc_temporal.timetravel_time', true)::timestamp,
    now()
  )::timestamp
  $$ language sql;

create or replace function
  pgvc_temporal.add_versioning_to_schema(schemaname text)
  returns void as $fn$
  declare
    tbl_name              text;
    tbl_cols              text;
    insert_tbl_col_values text;
    insert_tbl_cols       text;
    versioned_schemaname  text;
  begin
    versioned_schemaname := schemaname || '_versions';

    -- rename, so we don't have to copy the data
    execute format('alter schema %I rename to %I;', schemaname, versioned_schemaname);
    execute format('create schema if not exists %I;', schemaname);

    for tbl_name in
      execute format(
        $$ select table_name
           from information_schema.tables
           where table_schema = '%I_versions'
        $$,
        schemaname
      )
    loop
      -- can we, instead, loop over each constraint,
      --   and rather than dropping it,
      --   modify it to be scoped to the present?
      execute format('alter table %I.%I drop constraint if exists %I_pkey cascade', versioned_schemaname, tbl_name, tbl_name);

      execute format('alter table %I.%I add column pgvc_id      serial primary key',      versioned_schemaname, tbl_name);
      execute format('alter table %I.%I add column assert_time  timestamp default now()', versioned_schemaname, tbl_name);
      execute format('alter table %I.%I add column retract_time timestamp',               versioned_schemaname, tbl_name);

      execute format('create index if not exists %I_pgvc_id           on %I_versions.%I (pgvc_id)',      tbl_name, schemaname, tbl_name);
      execute format('create index if not exists %I_assert_time  on %I_versions.%I (assert_time)',  tbl_name, schemaname, tbl_name);
      execute format('create index if not exists %I_retract_time on %I_versions.%I (retract_time)', tbl_name, schemaname, tbl_name);

      execute format(
        $$ select string_agg(quote_ident(column_name), ', ') as names from information_schema.columns
           where table_schema = '%I_versions'
           and table_name = %L
           and column_name not in ('pgvc_id', 'assert_time', 'retract_time')
        $$,
        schemaname,
        tbl_name
      ) into tbl_cols;

      execute format(
        $$ create or replace view %I.%I as
           select $$ || tbl_cols || $$
           from %I.%I where assert_time <= pgvc_temporal.timetravel_time() and
           (retract_time > pgvc_temporal.timetravel_time() or retract_time is null)
        $$,
        schemaname,
        tbl_name,
        versioned_schemaname,
        tbl_name
      );

      execute format(
        $$ create or replace rule %I_delete as
           on delete to %I.%I
           where old.retract_time is null
           do instead
           update %I.%I
             set retract_time = now()
             where id = old.id;
        $$,
        tbl_name,
        versioned_schemaname, tbl_name,
        versioned_schemaname, tbl_name
      );

      execute format(
        $$ select string_agg('new.' || quote_ident(column_name), ', ') as names
           from information_schema.columns
           where table_schema = '%I_versions'
           and table_name = '%I'
           and column_name not IN ('pgvc_id', 'assert_time', 'retract_time')
        $$,
        schemaname,
        tbl_name
      ) into insert_tbl_col_values;

      execute format(
        $$ select string_agg(quote_ident(column_name), ', ') as names
           from information_schema.columns
           where table_schema = '%I_versions'
           and table_name = '%I'
           and column_name not in ('pgvc_id', 'assert_time', 'retract_time')
        $$,
        schemaname,
        tbl_name
      ) into insert_tbl_cols;

      execute format(
        $format$
        create function %I.%I_update_fn(old %I.%I, new %I.%I) returns void as $$
          begin
            update %I.%I
              set retract_time = now()
              where retract_time is null
              and id = old.id;

            insert into %I.%I (%s)
              values (%s);
          end $$ language plpgsql;
        $format$,
        schemaname, tbl_name,
        schemaname, tbl_name,
        schemaname, tbl_name,

        versioned_schemaname, tbl_name,
        versioned_schemaname, tbl_name,
        insert_tbl_cols,
        insert_tbl_col_values
      );

      execute format(
        $$ create or replace rule %I_update as
           on update to %I.%I
           do instead (select %I.%I_update_fn(old, new););
        $$,
        tbl_name,
        schemaname, tbl_name,
        schemaname, tbl_name
      );
  end loop;

  -- later: create the variable that stores the "effective time"

end $fn$ language plpgsql;
