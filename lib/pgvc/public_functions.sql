create function vc.init(system_user_ref varchar, default_branchname varchar)
returns void as $$
  declare
    root_commit    vc.commits;
    default_branch vc.branches;
  begin
    -- Create the initial commit
    root_commit.user_ref    := system_user_ref;
    root_commit.summary     := 'Initial commit';
    root_commit.description := '';
    root_commit.created_at  := now();
    root_commit.vc_hash     := vc.calculate_commit_hash(root_commit);
    insert into vc.commits select root_commit.*;

    -- Create the first branch
    insert into vc.branches (commit_hash, name, schema_name, is_default)
      values (root_commit.vc_hash, default_branchname, 'public', true)
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
  union all select * from vc.branches where is_default
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


create function vc.branch_create_branch(name varchar, commit_hash character(32))
returns vc.branches as $$
  declare
    branch vc.branches;
    db     vc.databases;
    table_name varchar;
    table_hash varchar;
    row_hashes character(32)[];
  begin
    -- create the branch
    insert into vc.branches (commit_hash, name, schema_name, is_default)
      values (commit_hash, name, '', false)
      returning * into branch;

    -- its schema_name is based on its id
    update vc.branches set schema_name = 'branch_'||branch.id
      where id = branch.id
      returning * into branch;

    -- get the database
    db := vc.get_database(commit_hash);

    -- create the schema
    execute format('create schema %s', quote_ident(branch.schema_name));

    -- for each table
    for table_name in
      select t.name from vc.tracked_tables t
    loop
      -- create the table
      execute format(
        'create table %s.%s (like public.%s including all);',
        quote_ident(branch.schema_name),
        quote_ident(table_name),
        quote_ident(table_name)
      );

      -- add the trigger
      execute format(
        $sql$
          create trigger vc_hash_and_record_%s_%s
          before insert or update on %s.%s
          for each row execute procedure vc.hash_and_record_row();
        $sql$,
        quote_ident(branch.schema_name),
        quote_ident(table_name),
        quote_ident(branch.schema_name),
        quote_ident(table_name)
      );

      -- insert the rows
      table_hash := db.table_hashes->table_name;
      row_hashes := (select tables.row_hashes from vc.tables where vc_hash = table_hash);
      execute format(
        $sql$
          insert into %s.%s
          select vc_record.*
          from unnest($1) as row_hash
          join vc.rows on vc_hash = row_hash
          join populate_record(null::%s.%s, data) as vc_record on true
        $sql$,
        quote_ident(branch.schema_name),
        quote_ident(table_name),
        quote_ident(branch.schema_name),
        quote_ident(table_name)
      ) using row_hashes;
    end loop;
    return branch;
  end $$ language plpgsql;



create function vc.track_table(tblname varchar) returns void as $$
  begin
    -- record that we care about this table
    insert into vc.tracked_tables (name) values (tblname)
      on conflict do nothing;

    /* SET session_replication_role = replica; */
    -- add vc_hash to the table
    execute format('alter table %s add column vc_hash character(32)', quote_ident(tblname));

    -- trigger to save its rows when they change
    execute format(
      $sql$
        create trigger vc_hash_and_record_%s
        before insert or update on %s
        for each row execute procedure vc.hash_and_record_row();
      $sql$,
      quote_ident(tblname),
      quote_ident(tblname)
    );

    -- fire the trigger for rows already in the table
    execute format('update %s set vc_hash = vc_hash', quote_ident(tblname));
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
    insert into vc.commits select cmt.*;
    insert into vc.ancestry (parent_hash, child_hash)
      values (branch.commit_hash, cmt.vc_hash);
    update vc.branches set commit_hash = cmt.vc_hash where id = branch.id;
    return cmt;
  end
  $$ language plpgsql;



create function vc.get_parents(in commit_hash character(32)) returns setof vc.commits as $$
  select commits.*
  from vc.ancestry
  join vc.commits on (ancestry.parent_hash = commits.vc_hash)
  where ancestry.child_hash = commit_hash;
  $$ language sql;



-- action: 'create' or 'delete'
create function vc.diff(in from_hash character(32), in to_hash character(32))
  returns table(action varchar, table_name varchar, hash character(32)) as $$
  begin
  end $$ language plpgsql;
