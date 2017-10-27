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
def find_ancestors_count(db, id)
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
      ),

      results (depth, id, val) AS (
        SELECT depth, strings.id, strings.val
        FROM unique_ancestors a
        JOIN strings ON (strings.id = a.id)
        ORDER BY a.depth -- add DESC to get the path from the root to the node in question
      )

    SELECT count(*) FROM results;
  SQL
end


# Insert the data:
depth   = 5000
numbers = 1.upto depth
string  = 'a'
strings = []
associations = []

numbers.each do |i|
  strings << string
  associations << [i-1, i] unless i == 1 # first one has no parent
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

# How much data?
db.exec('SELECT count(1) FROM strings;').to_a # => [{"count"=>"5000"}]
db.exec('SELECT count(1) FROM ancestry;').to_a # => [{"count"=>"4999"}]

# Get the hierarchy of the last char
def time
  pre_time  = Time.now
  result    = yield
  post_time = Time.now
  {seconds: post_time - pre_time, result: result}
end

# Run the query once to prime it
time { find_ancestors_count(db, depth).to_a }
# => {:seconds=>2.293476, :result=>[{"count"=>"5000"}]}

# And once to see how it performs
time { find_ancestors_count(db, depth-1).to_a }
# => {:seconds=>2.260849, :result=>[{"count"=>"4999"}]}
