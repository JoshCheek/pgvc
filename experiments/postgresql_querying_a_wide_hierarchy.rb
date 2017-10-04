require 'pg'

# Reset the database
lambda do
  db = PG.connect dbname: 'postgres'
  db.exec("DROP DATABASE IF EXISTS pg_git;")
  db.exec("CREATE DATABASE pg_git;")
end[]

db = PG.connect dbname: 'pg_git'

# The values being stored (going to use their id as the value)
db.exec <<-SQL
  CREATE TABLE strings (
    ID serial primary key,
    val varchar
  );
SQL

# Their relationship to each other
db.exec <<-SQL
  CREATE TABLE ancestry (
    parent_id int,
    child_id  int
  );
SQL


# Query the hierarchy out of the ancestors
def find_ancestors(db, id)
  db.exec_params <<-SQL, [id]
    WITH
      RECURSIVE ancestors (depth, id) AS (
        SELECT 0::integer, $1::integer

        UNION ALL

        SELECT prev.depth+1, crnt.parent_id
        FROM ancestors prev
        JOIN ancestry  crnt ON (prev.id = crnt.child_id)
      ),

      unique_ancestors (depth, id) AS (
        SELECT min(depth), id
        FROM ancestors
        GROUP BY id
      )

    SELECT depth, strings.*
    FROM unique_ancestors a
    JOIN strings ON (strings.id = a.id)
    ORDER BY a.depth; -- add DESC to get the path from the root to the node in question
  SQL
end


# Insert the data:
depth   = 19
max     = 2**depth - 1
numbers = 1.upto max
string  = 'a'
strings = []
associations = []

numbers.each do |i|
  strings << string
  associations << [i/2, i] unless i == 1 # first one has no parent
  string = string.succ
end

slice_size = 3000
strings.each_slice slice_size do |slice|
  values = slice.map.with_index(1) { |str, index| "($#{index})" }.join(", ")
  db.exec_params "INSERT INTO strings (val) VALUES #{values}", slice
end

associations.each_slice slice_size do |slice|
  values = slice.map.with_index do |(parent_id, child_id), index|
    "($#{index*2+1}, $#{index*2+2})"
  end.join(", ")
  db.exec_params "INSERT INTO ancestry (parent_id, child_id) VALUES #{values}", slice.flatten
end

# Add an index for performance
db.exec <<-SQL
  CREATE INDEX ancestry_child_id ON ancestry (child_id);
SQL

# How much data?
db.exec('SELECT count(1) FROM strings;').to_a # => [{"count"=>"524287"}]
db.exec('SELECT count(1) FROM ancestry;').to_a # => [{"count"=>"524286"}]

# Get the hierarchy of the last char
def time
  pre_time  = Time.now
  result    = yield
  post_time = Time.now
  {seconds: post_time - pre_time, result: result}
end

# Run the query once to prime it (reduces the time by a factor of 10)
time { find_ancestors(db, max).to_a }[:seconds] # => 0.003269

# And once to see how it performs (choosing a different id so it can't have cached the result)
time { find_ancestors(db, max-1).to_a }
# => {:seconds=>0.000488,
#     :result=>
#      [{"depth"=>"0", "id"=>"524286", "val"=>"acunv"},
#       {"depth"=>"1", "id"=>"262143", "val"=>"nwtk"},
#       {"depth"=>"2", "id"=>"131071", "val"=>"gkwe"},
#       {"depth"=>"3", "id"=>"65535", "val"=>"crxo"},
#       {"depth"=>"4", "id"=>"32767", "val"=>"avlg"},
#       {"depth"=>"5", "id"=>"16383", "val"=>"xfc"},
#       {"depth"=>"6", "id"=>"8191", "val"=>"lca"},
#       {"depth"=>"7", "id"=>"4095", "val"=>"fam"},
#       {"depth"=>"8", "id"=>"2047", "val"=>"bzs"},
#       {"depth"=>"9", "id"=>"1023", "val"=>"ami"},
#       {"depth"=>"10", "id"=>"511", "val"=>"sq"},
#       {"depth"=>"11", "id"=>"255", "val"=>"iu"},
#       {"depth"=>"12", "id"=>"127", "val"=>"dw"},
#       {"depth"=>"13", "id"=>"63", "val"=>"bk"},
#       {"depth"=>"14", "id"=>"31", "val"=>"ae"},
#       {"depth"=>"15", "id"=>"15", "val"=>"o"},
#       {"depth"=>"16", "id"=>"7", "val"=>"g"},
#       {"depth"=>"17", "id"=>"3", "val"=>"c"},
#       {"depth"=>"18", "id"=>"1", "val"=>"a"}]}
