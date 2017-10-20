create function vc.set_system_user_id(in id integer)
  returns void as $$
  begin
    update user_branches set is_system = false;
    insert into user_branches (user_id, branch_id, is_system)
      values (id, 1, true)
      on conflict (user_id) do update
      set is_system = EXCLUDED.is_system;
  end $$ language plpgsql
  set search_path = vc;


create function vc.track_table(in tblname varchar)
  returns void as $$
  begin
    insert into tracked_tables (name) values (tblname)
      on conflict do nothing;

    -- FIXME: Here is where we should add the trigger to the table
  end $$ language plpgsql
  set search_path = vc;

