create table database_hashes (
  hash varchar(32) primary key
);

create table table_hashes (
  hash varchar(32),
  name varchar not null
);

create table pg_git_tables (
  name varchar not null
);
