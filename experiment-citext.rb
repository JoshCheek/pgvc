#!/usr/bin/env ruby
db_from_name = "test-db-for-citext"


Dir.chdir __dir__

outstream = $outstream = $stdout # just b/c maybe it should be stderr, idk


def HEADER(name, outstream: $outstream)
  outstream.puts "\e[35m#{name}\e[0m"
end

def indent(text)
  text.gsub(/^/, "  ")
end


require 'open3'
def sh(command, echo: true, fail_on_err: true, print_err: true, outstream: $outstream)
  outstream.puts indent "$ #{command}" if echo
  out, err, status = Open3.capture3 command
  outstream.puts err if print_err && !err.empty?
  exit status.exitstatus if fail_on_err && !status.success?
  out
end


HEADER "Dropping DB: #{db_from_name}"
if sh(%[psql -c "SELECT datname FROM pg_database where datname = '#{db_from_name}';"], echo: false).include?(db_from_name)
  sh "dropdb '#{db_from_name}'"
  outstream.puts "  Dropped"
else
  outstream.puts "  Skipping (DNE)"
end


HEADER "Creating DB: #{db_from_name}"
sh "createdb '#{db_from_name}' -U admin"


HEADER "Making some tables"
sh %'psql -d "#{db_from_name}"  -c "\n#{<<~SQL.gsub('"', '\"')}"'
  CREATE TABLE table1 (
      id integer NOT NULL,
      name character varying(255)
  );
SQL


HEADER 'Adding some data'
sh %'psql -d "#{db_from_name}"  -c "\n#{<<~SQL.gsub('"', '\"')}"'
  INSERT INTO table1 (id, name)
  VALUES
    (1, 'TABLE1-A'),
    (2, 'table1-b'),
    (3, 'table1-c')
  ;
SQL


HEADER 'Switch to citext'
sh %'psql -d "#{db_from_name}"  -c "\n#{<<~SQL.gsub('"', '\"')}"'
  CREATE EXTENSION IF NOT EXISTS citext;

  -- ALTER TABLE table1 ADD COLUMN "name_citext" CITEXT;
  -- UPDATE table1 SET name_citext = name;
  ALTER TABLE table1 ALTER COLUMN "name" TYPE CITEXT;
SQL


HEADER 'The table now'
puts indent sh %'psql -d "#{db_from_name}"  -c "\n#{<<~SQL.gsub('"', '\"')}"'
  SELECT * from table1;
SQL

HEADER "Verify it works"
puts indent sh %'psql -d "#{db_from_name}"  -c "\n#{<<~SQL.gsub('"', '\"')}"'
  SELECT * from table1 where lower(name) = lower('Table1-a');
SQL
