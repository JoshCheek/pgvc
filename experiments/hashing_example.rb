require 'pg'
db = PG.connect(dbname: 'postgres')
db.exec("DROP DATABASE IF EXISTS pg_git;")
db.exec("CREATE DATABASE pg_git;")
db = PG.connect dbname: 'pg_git'

# =====  Structure  =====
hash = "varchar(32)" # size of md5
db.exec <<-SQL
  create table database_hashes (
    hash #{hash} primary key
  );
  create table table_hashes (
    hash #{hash},
    name varchar not null
  );
  create table pg_git_tables (
    name varchar not null
  );
SQL

# =====  Seed data  =====
db.exec <<-SQL
insert into pg_git_tables (name)
values ('table1'), ('table2');

insert into table_hashes (hash, name)
values ('d12dbd12d53ce0febf63eb41c5091a36', 'table1');

SQL

# =====  Functions  =====
db.exec <<-SQL
create or replace function table_hash(in tbl pg_git_tables)
returns #{hash} as $$
begin
  return md5('table:'||tbl.name);
end$$ language plpgsql;

create or replace function complete_commit()
returns integer as $$
declare
begin
  -- for each table, calculate its hash and possibly insert it into table_hashes
  insert into table_hashes (hash, name)
  select hash, name
  from (
    select
      table_hash(pg_git_tables) as hash,
      name
    from pg_git_tables
  ) t
  where hash not in (select hash from table_hashes);

  -- calculate the tables hash and possibly insert into database_hashes
  insert into database_hashes (hash)
  select md5('database:'||string_agg(hash, ','))
  from (
    select hash
    from table_hashes
    order by hash
  ) t;
  return 1;
end$$ language plpgsql;
SQL

# =====  Commit  =====
db.exec 'select complete_commit();'
db.exec('select * from table_hashes;').to_a
# => [{"hash"=>"d12dbd12d53ce0febf63eb41c5091a36", "name"=>"table1"},
#     {"hash"=>"072db2056ea084a77ec21dc70a5ddebe", "name"=>"table2"}]

db.exec('select * from database_hashes;').to_a
# => [{"hash"=>"1b21eae2e59aa204a3fe03847382beed"}]




