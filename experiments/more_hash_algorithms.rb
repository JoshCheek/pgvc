require 'pg'  # => true
# PG.connect(dbname: 'postgres').exec('drop database josh_testing')
# PG.connect(dbname: 'postgres').exec('create database josh_testing')

db = PG.connect(dbname: 'josh_testing')  # => #<PG::Connection:0x007fdf3faff2f0>
db.exec 'begin' # throws away changes when process exits

def db.exec(*)
  super.to_a
rescue Exception
  $!.set_backtrace caller.drop(1)
  raise
end

db.exec <<~SQL
  create extension pgcrypto;

  create or replace function sha1(bytea) returns text as $$
    select encode(digest($1, 'sha1'), 'hex')
    $$ language sql strict immutable;

  create or replace function sha256(bytea) returns text as $$
    select encode(digest($1, 'sha256'), 'hex')
    $$ language sql strict immutable;

  create or replace function sha512(bytea) returns text as $$
    select encode(digest($1, 'sha512'), 'hex')
    $$ language sql strict immutable;
SQL

# md5 already exists
db.exec "select    md5('some text')" # => [{"md5"=>"552e21cd4cd9918678e3c1a0df491bc3"}]
db.exec "select   sha1('some text')" # => [{"sha1"=>"37aa63c77398d954473262e1a0057c1e632eda77"}]
db.exec "select sha256('some text')" # => [{"sha256"=>"b94f6f125c79e3a5ffaa826f584c10d52ada669e6762051b826b55776d05aed2"}]
db.exec "select sha512('some text')" # => [{"sha512"=>"e2732baedca3eac1407828637de1dbca702c3fc9ece16cf536ddb8d6139cd85dfe7464b8235b29826f608ccf4ac643e29b19c637858a3d8710a59111df42ddb5"}]
