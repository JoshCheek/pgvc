create function vc.calculate_commit_hash(c vc.commits) returns character(32) as $$
  select md5(concat(
    c.db_hash,
    c.user_ref,
    c.summary,
    c.description,
    c.created_at::text
  )); $$ language sql;


create function vc.hash_row(in record anyelement, out vc_row vc.rows) as $$
  begin
    vc_row.data    := delete(hstore(record), 'vc_hash');
    vc_row.vc_hash := md5(vc_row.data::text);
  end $$ language plpgsql;


create function vc.record_that_were_tracking(table_name varchar) returns void as $$
  insert into vc.tracked_tables select table_name on conflict do nothing
  $$ language sql;


create function vc.fire_trigger_for_rows_in(table_name varchar) returns void as $$
  begin
    execute format('update %s set vc_hash = vc_hash', quote_ident(table_name));
  end $$ language plpgsql;


create function vc.add_hash_to_table(table_name varchar) returns void as $$
  begin
    execute format(
      'alter table %s add column vc_hash character(32)',
      quote_ident(table_name)
    );
  end $$ language plpgsql;


create function vc.hash_and_record_row() returns trigger as $$
  declare
    vc_row vc.rows;
  begin
    vc_row := vc.hash_row(NEW);
    insert into vc.rows select vc_row.* on conflict do nothing;
    NEW.vc_hash := vc_row.vc_hash;
    return NEW;
  end $$ language plpgsql;



create function vc.save_branch(schema_name varchar) returns character(32) as $$
  declare
    db vc.databases;
    table_name varchar;
  begin
    db.table_hashes := (
      select hstore(
        array_agg(name),
        array_agg(vc.save_table(schema_name, name))
      ) from vc.tracked_tables);
    db.table_hashes := coalesce(db.table_hashes, '');
    db.vc_hash := md5(db.table_hashes::text);
    insert into vc.databases select db.* on conflict do nothing;
    return db.vc_hash;
  end
  $$ language plpgsql;



create function vc.save_table
  ( in  schema_name varchar,
    in  table_name  varchar,
    out table_hash  character (32)
  ) as $$
  declare row_hashes character(32)[];
  begin
    execute format
      ( 'select array_agg(vc_hash) from %s.%s;',
        quote_ident(schema_name),
        quote_ident(table_name)
      ) into row_hashes;
    row_hashes := coalesce(row_hashes, '{}'); -- use empty array rather than null
    table_hash := md5(row_hashes::text);
    insert into vc.tables
      select table_hash, row_hashes
      on conflict (vc_hash) do nothing;
  end $$ language plpgsql;



create function vc.get_database(commit_hash character(32)) returns vc.databases as $$
  declare
    cmt vc.commits;
    db  vc.databases;
  begin
    cmt := vc.get_commit(commit_hash);
    db  := (select databases from vc.databases where vc_hash = cmt.db_hash);
    return db;
  end $$ language plpgsql;


create function vc.add_table_to_existing_schemas(table_name varchar) returns void as $$
  declare
    branch vc.branches;
  begin
    for branch in
      select * from vc.branches
    loop
      perform vc.ensure_table_exists_in_schema(branch.schema_name, table_name);
      perform vc.ensure_trigger_exists(branch.schema_name, table_name);
    end loop;
  end $$ language plpgsql;


create function vc.ensure_table_exists_in_schema(schema_name varchar, table_name varchar) returns void as $$
  begin
    execute format(
      'create table if not exists %s.%s (like public.%s including all);',
      quote_ident(schema_name),
      quote_ident(table_name),
      quote_ident(table_name)
    );
  end $$ language plpgsql;


create function vc.ensure_trigger_exists(schema_name varchar, table_name varchar) returns void as $fn$
  declare
    schema_ varchar := quote_ident(schema_name);
    table_  varchar := quote_ident(table_name);
  begin
    execute format(
      $$ drop trigger if exists vc_hash_and_record_%s_%s on %s.%s restrict;
      $$, schema_, table_, schema_, table_
    );
    execute format(
      $$ create trigger vc_hash_and_record_%s_%s
         before insert or update on %s.%s
         for each row execute procedure vc.hash_and_record_row();
      $$, schema_, table_, schema_, table_
    );
  end $fn$ language plpgsql;


create function vc.insert_branch(branch_name varchar, commit_hash character(32)) returns vc.branches as $$
  declare
    branch vc.branches;
  begin
    -- first create it, this way we get the id
    insert into vc.branches (commit_hash, name, schema_name, is_default)
      values (commit_hash, branch_name, '', false)
      returning * into branch;

    -- then update its schema_name based on its id
    update vc.branches set schema_name = 'branch_'||branch.id
      where id = branch.id
      returning * into branch;

    return branch;
  end $$ language plpgsql;


create function vc.create_schema(schema_name varchar) returns void as $$
  begin execute format('create schema %s;', quote_ident(schema_name));
  end $$ language plpgsql;


create function vc.insert_rows
  ( schema_name varchar,
    table_name  varchar,
    row_hashes  character(32)[]
  ) returns void as $$
  begin
    execute format(
      $sql$
        insert into %s.%s
        select vc_record.*
        from unnest($1) as row_hash
        join vc.rows on vc_hash = row_hash
        join populate_record(null::%s.%s, data) as vc_record on true
      $sql$,
      quote_ident(schema_name), quote_ident(table_name),
      quote_ident(schema_name), quote_ident(table_name)
    ) using row_hashes;
  end $$ language plpgsql;
