# RESULT: https://cl.ly/072w2h2a0d2X
def SECTION(name)
  if $stdout.tty?
    $stdout.puts "\e[35m=====  #{name}  =====\e[0m"
  else
    $stdout.puts "=====  #{name}  ====="
  end
end

require 'shellwords'
def log_command(command, *args)
  arg_str = args.map(&:shellescape).join " "
  if $stdout.tty?
    $stdout.puts "\e[34m$ \e[94m#{command}\e[0m #{arg_str}"
  else
    $stdout.puts "$ #{command} #{arg_str}"
  end
end

def log_error(message)
  $stderr.puts "\e[31m#{message}\e[0m"
end

require 'open3'
def sh(program, *args, &err_handler)
  log_command program, *args
  out, err, status = Open3.capture3 program, *args
  if status.success?
    out
  elsif err_handler
    err_handler.call out, err, status
  else
    raise err unless status.success?
  end
end

def cd(dir, &block)
  log_command 'cd', dir
  if block
    Dir.chdir(dir, &block)
  else
    Dir.chdir dir
    Dir.pwd
  end
end

require 'fileutils'
def mkdir_p(dir)
  log_command "mkdir", "-p", dir
  FileUtils.mkdir_p dir
end


SECTION 'Temp dir to work in'
cd __dir__
mkdir_p 'tmp'
cd 'tmp'


SECTION 'Download and extract postgres'
sh 'which', 'wget' do |out, err, status|
  log_error "Probably try installing wget (eg: `brew install wget`)"
  exit status.exitstatus
end

# Is there really not a program to take the 2 files and just error if they don't match?
# File.exist? 'postgresql-9.6-snapshot.tar.bz2.sha256' or
#   sh 'wget', 'https://ftp.postgresql.org/pub/snapshot/9.6/postgresql-9.6-snapshot.tar.bz2.sha256'

File.exist? 'postgresql-9.6-snapshot.tar.bz2' or
  sh 'wget', 'https://ftp.postgresql.org/pub/snapshot/9.6/postgresql-9.6-snapshot.tar.bz2'

File.exist? 'postgresql-9.6-snapshot.tar' or
  sh 'bunzip2', '--keep', 'postgresql-9.6-snapshot.tar.bz2'

Dir.exist? 'postgresql-9.6.5' or
  sh 'tar', '-xf', 'postgresql-9.6-snapshot.tar'


SECTION 'Turn on WAL_DEBUGGING'
cd 'postgresql-9.6.5'
# sh 'sed', '-i', '', 's/.*WAL_DEBUG.*/#define WAL_DEBUG/', 'src/include/pg_config_manual.h'

# https://www.postgresql.org/docs/9.6/static/install-short.html
# https://www.postgresql.org/docs/9.6/static/install-procedure.html
SECTION 'Building Postgresql'
mkdir_p '../build'
sh './configure', '--prefix=' << File.expand_path('../build', Dir.pwd),
                  '--with-pgport=9201',
                  '--enable-debug',
                  # '--enable-coverage',
                  '--enable-profiling',
                  '--enable-dtrace',
                  'CPPFLAGS=-DWAL_DEBUG' # I actually used the `sed` script above, found an SO post afterwards that said I could have done this

# AT THIS POINT I STARTED DOING IT MANUALLY:
SECTION 'Configure the compiled PG'
cd '../build'

# make
# make install
# bin/initdb /Users/xjxc322/code/pgvc/experiments/tmp/data
# echo 'wal_debug = 1' >> /Users/xjxc322/code/pgvc/experiments/tmp/data/postgresql.conf
# bin/postgres -D /Users/xjxc322/code/pgvc/experiments/tmp/data
# bin/createuser postgres
# bin/createdb josh_testing # in tab1
# bin/psql -d josh_testing  # in tab2
