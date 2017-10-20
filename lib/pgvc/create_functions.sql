create function vc.get_commit_hash(in c vc.commits) returns varchar(32) as $$
begin
  return md5(concat(
    c.db_hash,
    c.user_id::text,
    c.description,
    c.details,
    c.created_at::text,
    c.committed_at::text
  ));
end $$ language plpgsql;



create function vc.initialize(
    in system_user_id    integer,
    in default_branchname varchar
  ) returns void as $$
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

create function vc.get_branch(in userid integer) returns vc.branches as $$
  declare
    branch vc.branches;
  begin
    select branches.*
      from user_branches ub
      join branches on (ub.branch_id = branches.id)
      where ub.user_id = userid -- FIXME: how do I specify the argument, rather than changing names to not conflict?
      into branch
      limit 1;
    if branch.id is null then
      select * from branches where is_default into branch;
    end if;
    return branch;
  end $$ language plpgsql
  set search_path = vc;


create function vc.create_branch(in name varchar, in commit_hash character(32))
returns vc.branches as $$
  declare
    branch branches;
  begin
    insert into vc.branches (commit_hash, name, schema_name, is_default)
      values ( commit_hash, name, 'branch_'||quote_ident(name), false)
      returning * into branch;
    return branch;
  end $$ language plpgsql set search_path = vc;


create function vc.get_commit(in hash character(32))
  returns vc.commits as $$
  declare
    c vc.commits;
  begin
    select * from vc.commits where vc_hash = hash into c;
    return c;
  end $$ language plpgsql;

create function vc.track_table(in tblname varchar)
  returns void as $$
  begin
    insert into tracked_tables (name) values (tblname)
      on conflict do nothing;

    -- FIXME: Here is where we should add the trigger to the table
  end $$ language plpgsql
  set search_path = vc;
