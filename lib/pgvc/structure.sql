create extension if not exists hstore;

create schema vc;

create table vc.tracked_tables (
  name varchar unique
);

create table vc.rows (
  vc_hash character(32) primary key,
  data    public.hstore
);

create table vc.tables (
  vc_hash    character(32) primary key,
  row_hashes character(32)[]
);

create table vc.databases (
  vc_hash      character(32) primary key,
  table_hashes hstore
);

create table vc.commits (
  vc_hash      character(32) primary key,
  db_hash      character(32),
  user_ref     varchar   not null,
  summary      varchar   not null,
  description  text      not null,
  created_at   timestamp not null
);

create table vc.ancestry (
  parent_hash character(32),
  child_hash  character(32)
);

create table vc.branches (
  id          serial primary key, -- we only use this because we want it for schema names
  commit_hash character(32),
  name        varchar not null unique,
  schema_name varchar not null,
  is_default  boolean
);

create table vc.user_branches (
  user_ref  varchar primary key, -- make it an id of your users table, or a username or w/e
  branch_id integer,
  is_system boolean -- if true, this user is the one we should use when the system
);

create type vc.diff as (
  action     varchar, -- 'create' or 'delete'
  table_name varchar,
  vc_hash    character(32)
);
