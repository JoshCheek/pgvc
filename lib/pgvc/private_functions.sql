create function vc.calculate_commit_hash(c vc.commits) returns varchar(32) as $$
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


create function vc.record_that_were_tracking(in table_name varchar) returns void as $$
  insert into vc.tracked_tables select table_name on conflict do nothing
  $$ language sql;


create function vc.fire_trigger_for_rows_in(table_name varchar) returns void as $$
  begin
    execute format('update %s set vc_hash = vc_hash', quote_ident(table_name));
  end $$ language plpgsql;


create function vc.add_hash_to_table(in table_name varchar) returns void as $$
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


create function vc.add_trigger(in schema_name varchar, in table_name varchar) returns void as $$
  begin
    execute format(
      $sql$
        create trigger vc_hash_and_record_%s_%s
        before insert or update on %s.%s
        for each row execute procedure vc.hash_and_record_row();
      $sql$,
      quote_ident(schema_name),
      quote_ident(table_name),
      quote_ident(schema_name),
      quote_ident(table_name)
    );
  end $$ language plpgsql;


create function vc.save_branch(in schema_name varchar) returns character(32) as $$
  declare
    db vc.databases;
    table_name varchar;
  begin
    db.table_hashes := (
      select hstore(
        array_agg(name),
        array_agg(vc.save_table(schema_name, name))
      ) from vc.tracked_tables);
    db.vc_hash := md5(db.table_hashes::text);
    insert into vc.databases select db.* on conflict do nothing;
    return db.vc_hash;
  end
  $$ language plpgsql;



create function vc.save_table
  ( in  schema_name varchar,
    in  table_name  varchar,
    out table_hash  character(32)
  ) as $$
  declare row_hashes character(32)[];
  begin
    execute format('select array_agg(vc_hash) from %s.%s;',
                   quote_ident(schema_name),
                   quote_ident(table_name))
            into row_hashes;
    row_hashes := coalesce(row_hashes, '{}'); -- use empty array rather than null
    insert into vc.tables (vc_hash, row_hashes)
      values (md5(row_hashes::text), row_hashes)
      on conflict (vc_hash) do nothing
      returning vc_hash into table_hash;
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
