create schema git;

create function git.config_user_ref(name varchar) returns void as $$
  begin
    perform set_config('git.user_ref', name, false);
    perform git.checkout((git.current_branch()).name);
  end $$ language plpgsql;

create function git.current_user() returns varchar as $$
  select current_setting('git.user_ref')
  $$ language sql;

create function git.current_branch() returns vc.branches as $$
  select branches.*
    from vc.user_branches ub
    join vc.branches on (ub.branch_id = branches.id)
    where ub.user_ref = git.current_user()
  union all select * from vc.branches where is_default
  $$ language sql;

create function git.add_table(name varchar) returns void as $$
  begin perform vc.track_table(name);
  end $$ language plpgsql;

create function git.init() returns void as $$
  begin -- noop :P
  end $$ language plpgsql;

create function git.commit(message varchar) returns vc.commits as $$
  begin return vc.create_commit(
    message,
    ''::text,
    current_setting('git.user_ref'),
    now()::timestamp
  );
  end $$ language plpgsql;

-- FIXME: needs to actually look at the history
create function git.log() returns setof vc.commits as $$
  with
    recursive ancestors (depth, vc_hash) AS (
      select 0::integer, (git.current_branch()).commit_hash
      union all
      select prev.depth+1, crnt.parent_hash
      FROM ancestors   prev
      JOIN vc.ancestry crnt ON (prev.vc_hash = crnt.child_hash)
    ),
    unique_ancestors (depth, vc_hash) AS (
      select min(depth), vc_hash
      from ancestors
      group by vc_hash
    )
    select commits.*
    from unique_ancestors a
    join vc.commits using (vc_hash)
    order by a.depth -- add DESC to get the path from the root to the node in question
  $$ language sql;

create view git.branches as
  select branches.*, (branches.id = (git.current_branch()).id) as is_current
  from vc.branches;

create function git.branch() returns setof git.branches as $$
  select * from git.branches order by name;
  $$ language sql;

create function git.branch(new_branch_name varchar) returns vc.branches as $$
  begin return vc.user_create_branch(new_branch_name, git.current_user());
  end $$ language plpgsql;

create function git.checkout(branch_name varchar, out branch vc.branches) as $$
  begin
    branch := vc.switch_branch(git.current_user(), branch_name);
    if branch.is_default then
      execute format('set search_path = %s;', quote_ident(branch.schema_name));
    else
      execute format('set search_path = %s,public;', quote_ident(branch.schema_name));
    end if;
  end $$ language plpgsql;

