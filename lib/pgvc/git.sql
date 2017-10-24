create schema git;

create function git.config_user_ref(name varchar) returns void as $$
  begin perform set_config('git.user_ref', name, false);
  end $$ language plpgsql;

create function git.get_user() returns varchar as $$
  select current_setting('git.user_ref')
  $$ language sql;

create function git.current_branch() returns vc.branches as $$
  select branches.*
    from vc.user_branches ub
    join vc.branches on (ub.branch_id = branches.id)
    where ub.user_ref = git.get_user()
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
  select *
  from vc.commits
  where vc_hash = (git.current_branch()).commit_hash
  $$ language sql;

create view git.branches as
  select branches.*, (branches.id = (git.current_branch()).id) as is_current
  from vc.branches
  left join vc.user_branches on (branches.id = user_branches.branch_id);

create function git.branch() returns setof git.branches as $$
  select * from git.branches;
  $$ language sql;
