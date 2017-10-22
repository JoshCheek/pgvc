create function vc.calculate_commit_hash(c vc.commits) returns varchar(32) as $$
  select md5(concat(
    c.db_hash,
    c.user_id::text,
    c.summary,
    c.description,
    c.created_at::text
  )); $$ language sql;



create function vc.hash_and_record_row() returns trigger as $$
  declare
    serialized hstore;
  begin
    serialized := delete(hstore(NEW), 'vc_hash');
    NEW.vc_hash = md5(serialized::text);

    insert into vc.rows (vc_hash, data)
      select NEW.vc_hash, serialized
      where not exists (select vc_hash from vc.rows where vc_hash = NEW.vc_hash);

    return NEW;
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
    insert into vc.databases select db.*;
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
      returning vc_hash into table_hash;
  end $$ language plpgsql;
