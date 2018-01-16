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
        execute format('alter table %I.%I drop constraint %I_pkey cascade', versioned_schemaname, tbl_name, tbl_name);

        execute format('alter table %I.%I add column pgvc_id      serial primary key',      versioned_schemaname, tbl_name);
        execute format('alter table %I.%I add column assert_time  timestamp default now()', versioned_schemaname, tbl_name);
        execute format('alter table %I.%I add column retract_time timestamp',               versioned_schemaname, tbl_name);

        execute format('create index if not exists %I_pgvc_id           on %I_versions.%I (pgvc_id)',           tbl_name, schemaname, tbl_name);
        execute format('create index if not exists %I_pgvc_assert_time  on %I_versions.%I (assert_time)',  tbl_name, schemaname, tbl_name);
        execute format('create index if not exists %I_pgvc_retract_time on %I_versions.%I (retract_time)', tbl_name, schemaname, tbl_name);

        execute format(
          $$ select string_agg(column_name, ', ') as names from information_schema.columns
             where table_schema = '%I_versions'
             and table_name = %L
             and column_name not in ('pgvc_id', 'assert_time', 'retract_time')
          $$,
          schemaname,
          tbl_name
        ) into tbl_cols;

        execute format(
          $$ CREATE OR REPLACE VIEW %I.%I AS
             SELECT $$ || tbl_cols || $$
             FROM %I.%I WHERE assert_time <= pgvc_temporal.timetravel_time() AND
             (retract_time > pgvc_temporal.timetravel_time() OR retract_time IS NULL)
          $$,
          schemaname,
          tbl_name,
          versioned_schemaname,
          tbl_name
        );

        execute format(
          $$ CREATE OR REPLACE RULE %I_delete AS
             ON DELETE TO %I.%I
             WHERE OLD.retract_time IS NULL
             DO INSTEAD
             UPDATE %I.%I
               SET retract_time = now()
               WHERE id = OLD.id;
          $$,
          tbl_name,
          versioned_schemaname, tbl_name,
          versioned_schemaname, tbl_name
        );

        EXECUTE format('SELECT string_agg(''NEW.'' || column_name, '', '') as names FROM information_schema.columns
            WHERE table_schema = ''%I_versions''
            AND table_name = ''%I''
            AND column_name NOT IN (''pgvc_id'', ''assert_time'', ''retract_time'')', schemaname, tbl_name) INTO insert_tbl_col_values;

        EXECUTE format('SELECT string_agg(column_name, '', '') as names FROM information_schema.columns
            WHERE table_schema = ''%I_versions''
            AND table_name = ''%I''
            AND column_name NOT IN (''pgvc_id'', ''assert_time'', ''retract_time'')', schemaname, tbl_name) INTO insert_tbl_cols;

        execute format(
          $format$
          create function %I.%I_update_fn(old %I.%I, new %I.%I) returns void as $$
            begin
              UPDATE %I.%I
                SET retract_time = now()
                WHERE retract_time IS NULL
                AND id = OLD.id;

              INSERT INTO %I.%I (%s)
                VALUES (%s);
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
          $$ CREATE OR REPLACE RULE %I_update AS
             ON UPDATE TO %I.%I
             DO INSTEAD (select %I.%I_update_fn(OLD, NEW););
          $$,
          tbl_name,
          schemaname, tbl_name,
          schemaname, tbl_name
        );
    END LOOP;

    -- later: create the variable that stores the "effective time"

  end $fn$ language plpgsql;
