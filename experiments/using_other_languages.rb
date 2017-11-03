require 'pg'
# PG.connect(dbname: 'postgres').exec('drop database josh_testing')
# PG.connect(dbname: 'postgres').exec('create database josh_testing')
db = PG.connect(dbname: 'josh_testing')
db.exec 'begin' # throws away changes when process exits

def db.exec(*)
  super.to_a
end

# Available languages... why no lua?! :(
db.exec 'select tmplname from pg_pltemplate'
# => [{"tmplname"=>"plpgsql"},
#     {"tmplname"=>"pltcl"},
#     {"tmplname"=>"pltclu"},
#     {"tmplname"=>"plperl"},
#     {"tmplname"=>"plperlu"},
#     {"tmplname"=>"plpythonu"},
#     {"tmplname"=>"plpython2u"},
#     {"tmplname"=>"plpython3u"}]

# Currently available languages
db.exec 'select lanname from pg_language'
# => [{"lanname"=>"internal"},
#     {"lanname"=>"c"},
#     {"lanname"=>"sql"},
#     {"lanname"=>"plpgsql"}]

# Add Perl
db.exec 'create language plperlu'

# Now it's there!
db.exec 'select lanname from pg_language'
# => [{"lanname"=>"internal"},
#     {"lanname"=>"c"},
#     {"lanname"=>"sql"},
#     {"lanname"=>"plpgsql"},
#     {"lanname"=>"plperlu"}]

# Write a function in Perl
db.exec <<~SQL
  create or replace function ls(location text) returns text as $fn$
    use warnings;
    use strict;
    my $location = $_[0];
    my $output = `ls $location | tr "\n" ","`;
    return($output);
  $fn$ language plperlu;

  select * from ls('/')
  SQL
  # => [{"ls"=>
  #       "Applications,Library,Network,System,Users,Volumes,bin,cores,dev,etc,home,installer.failurerequests,macOS_SDK,net,opt,private,sbin,tmp,usr,var,"}]
