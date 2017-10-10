create or replace function table_hash(in tbl pg_git_tables)
returns varchar(32) as $$
begin
  return md5('table:'||tbl.name);
end$$ language plpgsql;


create or replace function complete_commit()
returns integer as $$
declare
begin
  -- for each table, calculate its hash and possibly insert it into table_hashes
  insert into table_hashes (hash, name)
  select hash, name
  from (
    select
      table_hash(pg_git_tables) as hash,
      name
    from pg_git_tables
  ) t
  where hash not in (select hash from table_hashes);

  -- calculate the tables hash and possibly insert into database_hashes
  insert into database_hashes (hash)
  select md5('database:'||string_agg(hash, ','))
  from (
    select hash
    from table_hashes
    order by hash
  ) t;
  return 1;
end$$ language plpgsql;
