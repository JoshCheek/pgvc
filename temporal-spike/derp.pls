DO
$$
DECLARE
	tbl record;
    schemaname text;
    tbl_cols text;
BEGIN
	schemaname := 'test1';
   	--EXECUTE format('ALTER SCHEMA %I RENAME TO %I_versions;', schemaname, schemaname);
	--EXECUTE format('CREATE SCHEMA %I;', schemaname);
	FOR tbl IN
    	EXECUTE format('SELECT table_name AS name FROM information_schema.tables WHERE table_schema = ''%I_versions''', schemaname)
    LOOP
    	--EXECUTE format('ALTER TABLE %I_versions.%I DROP CONSTRAINT %I_pkey CASCADE', schemaname, tbl.name, tbl.name);
    	--EXECUTE format('ALTER TABLE %I_versions.%I RENAME COLUMN id TO record_id', schemaname, tbl.name);
        --EXECUTE format('ALTER TABLE %I_versions.%I ADD COLUMN id SERIAL PRIMARY KEY', schemaname, tbl.name);
        --EXECUTE format('ALTER TABLE %I_versions.%I ADD COLUMN assert_time abstime', schemaname, tbl.name);
        --EXECUTE format('ALTER TABLE %I_versions.%I ADD COLUMN retract_time abstime', schemaname, tbl.name);
		EXECUTE format('SELECT string_agg(column_name, '', '') as names FROM information_schema.columns
        	WHERE table_schema = ''%I_versions''
            AND table_name = ''%I''
            AND column_name NOT IN (''id'', ''record_id'', ''assert_time'', ''retract_time'')', schemaname, tbl.name) INTO tbl_cols;
        
       	EXECUTE format('CREATE OR REPLACE VIEW %I.%I AS SELECT record_id as id, ' || tbl_cols || ' FROM %I_versions.%I;', schemaname, tbl.name, schemaname, tbl.name);
	END LOOP;
END; 
$$         