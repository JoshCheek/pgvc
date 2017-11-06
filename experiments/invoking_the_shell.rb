require 'pg'
# PG.connect(dbname: 'postgres').exec('drop database josh_testing')
# PG.connect(dbname: 'postgres').exec('create database josh_testing')
db = PG.connect(dbname: 'josh_testing')
db.exec 'begin' # throws away changes when process exits

def db.exec(*)
  super.to_a
end

# This is mostly just b/c I think it might be fun to add PL/pgSQL to
# https://github.com/JoshCheek/language-sampler-for-fullpath

# Sending data to a program
require 'tempfile'
f = Tempfile.open
db.exec <<~SQL
  copy (select 11, 22, 33)
  to program 'cat > #{f.path}'
  delimiter '-';
SQL
f.read # => "11-22-33\n"


# Reading data from a program (the data we read is a trace of the processes,
# mostly just b/c I'm curious... and yes, this is bash in sql in ruby O.o)
db.exec(<<~SQL).map { |r| r['stdout'] }
  create temp table process_trace (stdout text);
  copy process_trace (stdout) from program $bash$
          pid="$$"
          while true; do
            ps -p "$pid" -o "pid command" | sed 1d
            pid="$(ps -p "$pid" -o ppid | sed 1d)"
            [[ -z "$pid" ]] && break
          done
  $bash$;

  select * from process_trace;
  SQL
  # => ["31973 sh -c \n" +
  #    "        pid=\"$$\"\n" +
  #    "        while true; do\n" +
  #    "          ps -p \"$pid\" -o \"pid command\" | sed 1d\n" +
  #    "          pid=\"$(ps -p \"$pid\" -o ppid | sed 1d)\"\n" +
  #    "          [[ -z \"$pid\" ]] && break\n" +
  #    "        done\n",
  #     "31970 postgres: xjxc322 josh_testing [local] COPY  ",
  #     "  710 /usr/local/opt/postgresql/bin/postgres -D /usr/local/var/postgres",
  #     "    1 /sbin/launchd"]
