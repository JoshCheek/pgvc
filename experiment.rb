#!/usr/bin/env ruby
db_from_name = "test-db-for-copying-schema"
dump_file = 'data.sql'


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
  CREATE TABLE table2 (
      id integer NOT NULL,
      name character varying(255)
  );
SQL


HEADER 'Adding some data'
sh %'psql -d "#{db_from_name}"  -c "\n#{<<~SQL.gsub('"', '\"')}"'
  INSERT INTO table1 (id, name)
  VALUES
    (1, 'table1-a'),
    (2, 'table1-b'),
    (3, 'table1-c')
  ;
  INSERT INTO table2 (id, name)
  VALUES
    (1, 'table2-a'),
    (2, 'table2-b'),
    (3, 'table2-c')
  ;
  CREATE INDEX table1_name_index ON table1 USING btree (name);
SQL


HEADER 'Creating second schema'
sh %'psql -d "#{db_from_name}"  -c "CREATE SCHEMA pcr;"'


HEADER 'Copying data to new schema'
File.delete dump_file if File.exist? dump_file
# need the --blobs flag?
#
# -b
# --blobs
# Include large objects in the dump. This is the default behavior except when --schema, --table,
# # or --schema-only is specified. The -b switch is therefore only useful to add large objects to
# dumps where a specific schema or table has been requested. Note that blobs are considered data
# and therefore will be included when --data-only is used, but not when --schema-only is.
sh "pg_dump --schema=public #{db_from_name} | sed '/^SET search_path/s/public,/pcr,/' > #{dump_file}"
sh "psql -d #{db_from_name} -f #{dump_file}"


HEADER 'Querying to verify'
outstream.puts indent sh "psql -d #{db_from_name} -c 'select * from public.table1 JOIN pcr.table1 ON public.table1.id = pcr.table1.id'"
outstream.puts indent sh "psql -d #{db_from_name} -c 'select * from public.table2 JOIN pcr.table2 ON public.table2.id = pcr.table2.id'"

HEADER "Dumping the pcr schema"
outstream.puts indent sh "pg_dump --schema=pcr #{db_from_name} > data-pcr.sql"
