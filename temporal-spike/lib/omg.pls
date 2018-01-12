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
  pgvc_temporal.addVersioningToSchema(schemaname text)
  returns void as $fn$
  declare
      tbl                  record;
      tbl_cols             text;
      versioned_schemaname text;
  begin
    versioned_schemaname := schemaname || '_versions';

    EXECUTE format('ALTER SCHEMA %I RENAME TO %I;', schemaname, versioned_schemaname);
    EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I;', schemaname);
    -- EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I_future;', schemaname);

    FOR tbl IN
        EXECUTE format('SELECT table_name AS name FROM information_schema.tables WHERE table_schema = ''%I_versions''', schemaname)
        -- EXECUTE format(
        --   $$ SELECT table_name AS name
        --      FROM   information_schema.tables
        --      WHERE  table_schema = %L
        --   $$,
        --   schemaname
        -- )
    LOOP
        EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I_pkey CASCADE',              versioned_schemaname, tbl.name, tbl.name);
        EXECUTE format('ALTER TABLE %I.%I RENAME COLUMN id TO record_id',                versioned_schemaname, tbl.name);
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN id SERIAL PRIMARY KEY',             versioned_schemaname, tbl.name);
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN assert_time timestamp DEFAULT now()', versioned_schemaname, tbl.name);
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN retract_time timestamp',              versioned_schemaname, tbl.name);

        EXECUTE format('CREATE INDEX IF NOT EXISTS %I_record_id ON %I_versions.%I (record_id)', tbl.name, schemaname, tbl.name);
        EXECUTE format('CREATE INDEX IF NOT EXISTS %I_assert_time ON %I_versions.%I (assert_time)', tbl.name, schemaname, tbl.name);
        EXECUTE format('CREATE INDEX IF NOT EXISTS %I_retract_time ON %I_versions.%I (retract_time)', tbl.name, schemaname, tbl.name);

        -- TODO: set assert_time

        -- EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS %I_have_a_single_future_version ON %I_versions.%I (record_id) WHERE assert_time IS NULL',
        --           tbl.name,
        --           schemaname,
        --           tbl.name
        --         );

        EXECUTE format('SELECT string_agg(column_name, '', '') as names FROM information_schema.columns
            WHERE table_schema = ''%I_versions''
            AND table_name = ''%I''
            AND column_name NOT IN (''id'', ''record_id'', ''assert_time'', ''retract_time'')', schemaname, tbl.name) INTO tbl_cols;

        -- EXECUTE format(
        --   $$ SELECT string_agg(column_name, ', ') as names
        --      FROM information_schema.columns
        --      WHERE table_schema = '%I'
        --      AND table_name = '%I'
        --      AND column_name NOT IN ('id', 'record_id', 'assert_time', 'retract_time')
        --   $$,
        --   versioned_schemaname,
        --   tbl.name
        -- )
        -- INTO tbl_cols;

        EXECUTE format(
          'CREATE OR REPLACE VIEW %I.%I AS' ||
            ' SELECT record_id as id, ' || tbl_cols ||
            ' FROM %I.%I WHERE assert_time <= pgvc_temporal.timetravel_time() AND' ||
            ' (retract_time > pgvc_temporal.timetravel_time() OR retract_time IS NULL)' ||
            ' ORDER BY record_id ASC, id DESC;', schemaname, tbl.name, versioned_schemaname, tbl.name);

        execute format(
          $$ CREATE OR REPLACE RULE %I_delete AS
             ON DELETE TO %I.%I
             DO INSTEAD
             UPDATE %I.%I
               SET retract_time = now()
               WHERE id = OLD.id;
          $$,
          tbl.name,
          versioned_schemaname, tbl.name,
          versioned_schemaname, tbl.name
        );

        /* execute format( */
        /*   $$ CREATE OR REPLACE RULE %I_update AS */
        /*      ON UPDATE TO %I.%I */
        /*      DO INSTEAD */
        /*      UPDATE %I.%I */
        /*        SET retract_time = now() */
        /*        WHERE id = OLD.id; */
        /*      INSERT INTO %I.%I */
        /*       VALUES ( */
        /*   $$, */
        /*   tbl.name, */
        /*   versioned_schemaname, tbl.name, */
        /*   versioned_schemaname, tbl.name, */
        /*   versioned_schemaname, tbl.name */
        /* ); */

        /* CREATE RULE %I.%I_insert AS */
        /*   ON INSERT TO %I.%I */
        /*   DO INSTEAD */
        /*   INSERT INTO %I.%I VALUES (NEW.sl_name); */
        /* versioned_schemaname, tbl.name, */
        /* versioned_schemaname, tbl.name, */
        /* versioned_schemaname, tbl.name, */

        --EXECUTE format('CREATE OR REPLACE VIEW %I_future.%I AS SELECT DISTINCT(record_id) as id, ' || tbl_cols || ' FROM %I_versions.%I WHERE (assert_time <= now() OR assert_time IS NULL) ORDER BY record_id ASC, id DESC;', schemaname, tbl.name, schemaname, tbl.name);
    END LOOP;

    -- later: create the variable that stores the "effective time"

  end $fn$ language plpgsql;
