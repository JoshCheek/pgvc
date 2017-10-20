create extension if not exists hstore;

create schema vc;

create table vc.tracked_tables (
  name varchar unique
);

create table vc.tables (
  vc_hash    character(32),
  row_hashes character(32)[]
);

create table vc.rows (
  vc_hash character(32),
  data    public.hstore
);

create table vc.user_branches (
  user_id   integer primary key,
  branch_id integer,
  is_system boolean
);
