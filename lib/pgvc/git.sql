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
  begin end $$ language plpgsql; -- noop :P


create function git.commit(message varchar) returns vc.commits as $$
  begin
    return vc.create_commit(
      message,
      ''::text,
      current_setting('git.user_ref'),
      now()::timestamp
    );
  end $$ language plpgsql;


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
  begin
    return vc.user_create_branch(new_branch_name, git.current_user());
  exception when unique_violation then
    raise 'A branch named ''%'' already exists.', new_branch_name
          using errcode = 'unique_violation';
  end $$ language plpgsql;


create function git.checkout(branch_name varchar, out branch vc.branches) as $$
  begin
    branch := vc.switch_branch(git.current_user(), branch_name);
    execute format('set search_path = %s,public;', quote_ident(branch.schema_name));
  exception when syntax_error then
    raise '''%'' did not match any branches known to pgvc', branch_name
          using errcode = 'no_data_found';
  end $$ language plpgsql;


create function git.diff() returns setof vc.diff as $$
  declare
    branch       vc.branches;
    vccommit     vc.commits;
    current_hash character(32);
  begin
    branch       := git.current_branch();
    vccommit     := (select commits from vc.commits where commits.vc_hash = branch.commit_hash);
    current_hash := vc.save_branch(branch.schema_name);
    return query select * from vc.diff_databases(vccommit.db_hash, current_hash);
  end $$ language plpgsql;


create function git.diff(ref varchar) returns setof vc.diff as $$
  declare
    crnt_branch  vc.branches;
    other_branch vc.branches;
    other_commit vc.commits;
    current_hash character(32);
  begin
    crnt_branch  := git.current_branch();
    current_hash := vc.save_branch(crnt_branch.schema_name);

    other_branch := (select branches from vc.branches where name = ref);
    if other_branch is not null then
      other_commit := (select commits from vc.commits where commits.vc_hash = other_branch.commit_hash);
    else
      other_commit := (select commits from vc.commits where commits.vc_hash = ref);
    end if;
    return query select * from vc.diff_databases(other_commit.db_hash, current_hash);
  end $$ language plpgsql;
