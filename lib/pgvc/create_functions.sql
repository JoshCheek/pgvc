create function vc.calculate_commit_hash(c vc.commits) returns varchar(32) as $$
  select md5(concat(
    c.db_hash,
    c.user_id::text,
    c.summary,
    c.description,
    c.created_at::text
  )); $$ language sql;



create function vc.initialize(system_user_id integer, default_branchname varchar)
returns void as $$
  declare
    root_commit    vc.commits;
    default_branch vc.branches;
  begin
    -- Create the initial commit
    root_commit.user_id     := system_user_id;
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
    insert into vc.user_branches (user_id, branch_id, is_system)
      values (system_user_id, default_branch.id, true);
  end $$ language plpgsql;



create function vc.get_branch(user_id integer) returns vc.branches as $$
  select branches.*
    from vc.user_branches ub
    join vc.branches on (ub.branch_id = branches.id)
    where ub.user_id = $1
  union all
  -- default for if the user has never checked out a branch
  select * from vc.branches where is_default
  $$ language sql;



create function vc.get_branches() returns setof vc.branches as $$
  select * from vc.branches
  $$ language sql;


create function vc.create_branch_from_current(name varchar, user_id integer)
  returns vc.branches as $$
  declare
    branch vc.branches;
  begin
    branch := vc.get_branch(user_id);
    branch := vc.create_branch(name, branch.commit_hash);
    return branch;
  end $$ language plpgsql;


create function vc.rename_branch(oldname varchar, newname varchar) returns vc.branches as $$
  update vc.branches set name = newname where name = oldname returning *
  $$ language sql;

create function vc.delete_branch(branch_name varchar) returns vc.branches as $$
  delete from vc.branches where branches.name = branch_name returning *
  $$ language sql;

create function vc.switch_branch(userid integer, branch_name varchar, out branch vc.branches) as $$
  begin
    branch := (select branches from vc.branches where name = branch_name);
    insert into vc.user_branches (user_id, branch_id, is_system)
      values (userid, branch.id, false)
      on conflict (user_id) do update set branch_id = EXCLUDED.branch_id;
  end $$ language plpgsql;


create function vc.create_branch(name varchar, commit_hash character(32))
returns vc.branches as $$
  insert into vc.branches (commit_hash, name, schema_name, is_default)
    values ( commit_hash, name, 'branch_'||quote_ident(name), false)
    returning *;
  $$ language sql;


create function vc.hash_and_record_row() returns trigger as $$
  declare
    serialized hstore;
  begin
    select hstore(NEW) into serialized;
    select delete(serialized, 'vc_hash') into serialized;
    NEW.vc_hash = md5(serialized::text);

    insert into vc.rows (vc_hash, data)
      select NEW.vc_hash, serialized
      where not exists (select vc_hash from vc.rows where vc_hash = NEW.vc_hash);

    return NEW;
  end $$ language plpgsql;



create function vc.track_table(tblname varchar) returns void as $$
  begin
    -- record that we care about this table
    insert into vc.tracked_tables (name) values (tblname)
      on conflict do nothing;

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



create function vc.create_commit
  ( in summary     vc.commits.summary%TYPE,
    in description vc.commits.description%TYPE,
    in user_id     vc.commits.user_id%TYPE,
    in created_at  vc.commits.created_at%TYPE
  ) returns vc.commits as $$
  declare
    cmt vc.commits;
    branch vc.branches;
  begin
    branch          := vc.get_branch(user_id);
    cmt.summary     := summary;
    cmt.description := description;
    cmt.user_id     := user_id;
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
