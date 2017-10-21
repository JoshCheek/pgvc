create function vc.get_commit_hash(c vc.commits) returns varchar(32) as $$
  select md5(concat(
    c.db_hash,
    c.user_id::text,
    c.description,
    c.details,
    c.created_at::text,
    c.committed_at::text
  )); $$ language sql;



create function vc.initialize(system_user_id integer, default_branchname varchar)
returns void as $$
  declare
    root_commit    vc.commits;
    default_branch vc.branches;
  begin
    -- Create the initial commit
    root_commit.user_id      := system_user_id;
    root_commit.description  := 'Initial commit';
    root_commit.details      := '';
    root_commit.created_at   := now();
    root_commit.committed_at := now();
    root_commit.vc_hash      := vc.get_commit_hash(root_commit);
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
  -- default for if the user has never checked out a branch
  select * from vc.branches where is_default
  union
  -- FIXME: This hasn't been tested yet
  select branches.*
    from vc.user_branches ub
    join vc.branches on (ub.branch_id = branches.id)
    where ub.user_id = $1
  $$ language sql;



/* create function vc.create_branch(name varchar, commit_hash character(32)) */
/* returns vc.branches as $$ */
/*   insert into vc.branches (commit_hash, name, schema_name, is_default) */
/*     values ( commit_hash, name, 'branch_'||quote_ident(name), false) */
/*     returning *; */
/*   $$ language sql; */


create function vc.get_commit(commit_hash character(32)) returns vc.commits as $$
  select * from vc.commits where vc_hash = commit_hash
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
