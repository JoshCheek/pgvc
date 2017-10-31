create function vc.init(system_user_ref varchar, default_branchname varchar)
returns void as $$
  declare
    default_branch vc.branches;
  begin
    -- Create the first branch
    insert into vc.branches (commit_hash, name, schema_name, is_default)
      values (null, default_branchname, 'public', true)
      returning *
      into default_branch;

    -- Save the system user id to that branch
    insert into vc.user_branches (user_ref, branch_id, is_system)
      values (system_user_ref, default_branch.id, true);
  end $$ language plpgsql;



create function vc.user_get_branch(user_ref varchar) returns vc.branches as $$
  select branches.*
    from vc.user_branches ub
    join vc.branches on (ub.branch_id = branches.id)
    where ub.user_ref = $1
  -- default for if the user has never checked out a branch
  union all
  select * from vc.branches where is_default
  $$ language sql;



create function vc.get_branches() returns setof vc.branches as $$
  select * from vc.branches
  $$ language sql;


create function vc.rename_branch(oldname varchar, newname varchar) returns vc.branches as $$
  update vc.branches set name = newname where name = oldname returning *
  $$ language sql;

create function vc.delete_branch(branch_name varchar) returns vc.branches as $$
  declare branch vc.branches;
  begin
    branch := (select branches from vc.branches where branches.name = branch_name);
    if branch.is_default then
      raise 'Cannot delete %, it''s the default branch, the system expects it to exist',
            branch_name
            using errcode = 'data_exception';
    end if;
    delete from vc.branches where id = branch.id;
    return branch;
  end
  $$ language plpgsql;


create function vc.switch_branch(_user_ref varchar, branch_name varchar, out branch vc.branches) as $$
  begin
    branch := (select branches from vc.branches where name = branch_name);
    insert into vc.user_branches (user_ref, branch_id, is_system)
      values (_user_ref, branch.id, false)
      on conflict (user_ref) do update set branch_id = EXCLUDED.branch_id;
  end $$ language plpgsql;


create function vc.user_create_branch(name varchar, user_ref varchar) returns vc.branches as $$
  begin
    return vc.branch_create_branch(name, (vc.user_get_branch(user_ref)).commit_hash);
  end $$ language plpgsql;


create function vc.branch_create_branch(
  in  branch_name varchar,
  in  commit_hash character(32),
  out branch      vc.branches
) as $$
  declare
    db         vc.databases;
    table_name varchar;
    table_hash varchar;
  begin
    branch := vc.insert_branch(branch_name, commit_hash);
    db     := vc.get_database(commit_hash);
    perform vc.create_schema(branch.schema_name);

    for table_name in
      select name from vc.tracked_tables
    loop
      table_hash := db.table_hashes->table_name;
      perform vc.ensure_table_exists_in_schema(branch.schema_name, table_name);
      perform vc.ensure_trigger_exists(branch.schema_name, table_name);
      perform vc.insert_rows(
        branch.schema_name,
        table_name,
        (select row_hashes from vc.tables where vc_hash = table_hash)
      );
    end loop;
  end $$ language plpgsql;



-- Maybe useful for reducing the time it takes?
--   SET session_replication_role = replica;
-- Okay, thenthereisalso turning off autovacuum:
--   execute format('ALTER TABLE %s SET (autovacuum_enabled = false, toast.autovacuum_enabled = false);',
--   quote_ident(table_name));
-- And something about savepoints or checkpoints or smth
--   set checkpoint_completion_target to 0.9;
create function vc.track_table(table_name varchar) returns void as $$
  begin
    perform vc.add_hash_to_table(table_name);
    perform vc.ensure_trigger_exists('public', table_name);
    perform vc.fire_trigger_for_rows_in(table_name);
    perform vc.record_that_were_tracking(table_name);
    perform vc.add_table_to_existing_schemas(table_name);
  end $$ language plpgsql;



create function vc.get_commit(commit_hash character(32)) returns vc.commits as $$
  select * from vc.commits where vc_hash = commit_hash
  $$ language sql;



create function vc.create_commit
  ( in summary     vc.commits.summary%TYPE,
    in description vc.commits.description%TYPE,
    in user_ref    vc.commits.user_ref%TYPE,
    in created_at  vc.commits.created_at%TYPE
  ) returns vc.commits as $$
  declare
    cmt vc.commits;
    branch vc.branches;
  begin
    branch          := vc.user_get_branch(user_ref);
    cmt.summary     := summary;
    cmt.description := description;
    cmt.user_ref    := user_ref;
    cmt.created_at  := created_at;
    cmt.db_hash     := vc.save_branch(branch.schema_name);
    cmt.vc_hash     := vc.calculate_commit_hash(cmt);
    -- FIXME: iffy, its conflicting b/c it doesn't encode its parents hashes within it
    insert into vc.commits select cmt.*
      on conflict do nothing;
    -- FIXME: if the above conflicted, then we shouldn't double-add its parent
    -- get a test to show this, and then, also, assert the uniqueness of the join table
    insert into vc.ancestry (parent_hash, child_hash)
      values (branch.commit_hash, cmt.vc_hash);
    update vc.branches set commit_hash = cmt.vc_hash where id = branch.id;
    return cmt;
  end
  $$ language plpgsql;



create function vc.get_parents(commit_hash character(32)) returns setof vc.commits as $$
  select commits.*
  from vc.ancestry
  join vc.commits on (ancestry.parent_hash = commits.vc_hash)
  where ancestry.child_hash = commit_hash;
  $$ language sql;


create function vc.diff_commits(from_hash character(32), to_hash character(32)) returns setof vc.diff as $$
  begin
    return query select * from vc.diff_databases(
      (select db_hash from vc.commits c where c.vc_hash = from_hash),
      (select db_hash from vc.commits c where c.vc_hash = to_hash)
    );
  end $$ language plpgsql;


create function vc.diff_databases(from_hash character(32), to_hash character(32)) returns setof vc.diff as $$
  begin
    return query select * from vc.diff_tables(
      (select table_hashes from vc.databases d where d.vc_hash = from_hash),
      (select table_hashes from vc.databases d where d.vc_hash = to_hash)
    );
  end $$ language plpgsql;


create function vc.diff_tables(from_tables hstore, to_tables hstore) returns setof vc.diff as $$
  declare
    changed_tables varchar[];
    table_name     varchar;
  begin
    changed_tables := akeys(coalesce(
      (from_tables-to_tables)||(to_tables-from_tables), -- FIXME: no tests on the bidirectionality of this
      to_tables,
      from_tables -- FIXME: not tested (haven't even tried running it yet it)
    ));

    foreach table_name in array changed_tables
    loop
      return query select * from vc.diff_rows(
        table_name,
        (select row_hashes from vc.tables where tables.vc_hash = from_tables->table_name),
        (select row_hashes from vc.tables where tables.vc_hash = to_tables->table_name)
      );
    end loop;
  end $$ language plpgsql;


create function vc.diff_rows(table_name varchar, from_rows character(32)[], to_rows character(32)[])
  returns setof vc.diff as $$
    with
    f      as (select unnest(from_rows) as vc_hash),
    t      as (select unnest(to_rows)   as vc_hash),
    f_only as (select f.vc_hash from f left  join t on (f = t) where t is null),
    t_only as (select t.vc_hash from f right join t on (f = t) where f is null)
    select 'delete', table_name, vc_hash from f_only
    union all
    select 'insert', table_name, vc_hash from t_only
  $$ language sql;


create function vc.populate_vc_record(table_name varchar, vc_row vc.rows) returns record as $$
  declare
    r record;
  begin
    execute format
      ( 'select vc_record.* from populate_record(null::%s, $1) as vc_record',
        quote_ident(table_name)
      )
      using vc_row.data
      into r;
    r.vc_hash = vc_row.vc_hash;
    return r;
  end $$ language plpgsql;
