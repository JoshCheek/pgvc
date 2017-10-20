create function vc.get_commit_hash(c vc.commits) returns varchar(32) as $$
  select md5(concat(
    c.db_hash,
    c.user_id::text,
    c.description,
    c.details,
    c.created_at::text,
    c.committed_at::text
  ));
$$ language sql;



create function vc.initialize(system_user_id integer, default_branchname varchar)
returns void as $$
  declare
    root_commit    vc.commits;
    default_branch vc.branches;
  begin
    -- Create the initial commit
    root_commit.user_id      = system_user_id;
    root_commit.description  = 'Initial commit';
    root_commit.details      = '';
    root_commit.created_at   = now();
    root_commit.committed_at = now();
    root_commit.vc_hash      = get_commit_hash(root_commit);
    insert into commits select root_commit.*;

    -- Create the first branch
    default_branch = create_branch(default_branchname, root_commit.vc_hash);
    default_branch.is_default = true;
    /* select create_branch(default_branch, root_commit.vc_hash) into default_branch; */
    update branches set is_default = true where id = default_branch.id;

    -- Save the system user id to that branch
    insert into user_branches (user_id, branch_id, is_system)
      values (system_user_id, default_branch.id, true);
  end $$ language plpgsql
  set search_path = vc;


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


create function vc.create_branch(name varchar, commit_hash character(32))
returns vc.branches as $$
  insert into vc.branches (commit_hash, name, schema_name, is_default)
    values ( commit_hash, name, 'branch_'||quote_ident(name), false)
    returning *;
  $$ language sql;


create function vc.get_commit(commit_hash character(32)) returns vc.commits as $$
  select * from vc.commits where vc_hash = commit_hash
  $$ language sql;


create function vc.track_table(tblname varchar) returns void as $$
  begin
    insert into tracked_tables (name) values (tblname)
      on conflict do nothing;

    -- FIXME: Here is where we should add the trigger to the table
  end $$ language plpgsql
  set search_path = vc;
