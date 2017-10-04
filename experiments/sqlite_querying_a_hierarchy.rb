# A database to query
require "sqlite3"
db = SQLite3::Database.new ":memory:"

# The values being stored (going to use their id as the value)
db.execute <<-SQL
  CREATE TABLE chars (
    ID integer primary key,
    val string
  );
SQL

# Their relationship to each other
db.execute <<-SQL
  CREATE TABLE ancestry (
    parent_id int,
    child_id  int
  );
SQL

# Query the hierarchy out of the ancestors
def find_ancestors(db, id)
  db.execute <<-SQL, id
    WITH RECURSIVE ancestors
      (depth, id)
    AS (
      SELECT 0, ?

      UNION ALL

      SELECT prev.depth+1, crnt.parent_id
      FROM ancestors prev
      JOIN ancestry  crnt ON (prev.id = crnt.child_id)
    )
    SELECT chars.*
    FROM ancestors
    JOIN chars ON (chars.id = ancestors.id)
    ORDER BY ancestors.depth; -- add DESC to get the path from the root to the node in question
  SQL
end


# A simple map from id to character
def char_for(id)
  ('A'.ord + id-1).chr
end

# Build the data:
#               1A
#       2B              3C
#   4D     5E        6F       7G
# 8H 9I  10J 11K   12L 13M  14N 15O
depth = 4
numbers = 1.upto 2**depth - 1
numbers.each do |i|
  db.execute "INSERT INTO chars (val) VALUES (?)", char_for(i)
  next if i == 1 # first char, "A", has no parent
  db.execute "INSERT INTO ancestry (parent_id, child_id) VALUES (?, ?)", i/2, i
end

# Validate
db.execute('SELECT * FROM chars;').map(&:join).join(" ")
# => "1A 2B 3C 4D 5E 6F 7G 8H 9I 10J 11K 12L 13M 14N 15O"

db.execute <<-SQL
  SELECT chars.* FROM chars
  JOIN ancestry ON (chars.id = ancestry.child_id)
  WHERE ancestry.parent_id = 6 -- "F"'s children are "L" and "M"
SQL
# => [[12, "L"], [13, "M"]]

# Get the hierarchy of each character
db.execute('SELECT * FROM chars;').map do |id, char|
  find_ancestors(db, id).map(&:last)
end
# => [["A"],
#     ["B", "A"],
#     ["C", "A"],
#     ["D", "B", "A"],
#     ["E", "B", "A"],
#     ["F", "C", "A"],
#     ["G", "C", "A"],
#     ["H", "D", "B", "A"],
#     ["I", "D", "B", "A"],
#     ["J", "E", "B", "A"],
#     ["K", "E", "B", "A"],
#     ["L", "F", "C", "A"],
#     ["M", "F", "C", "A"],
#     ["N", "G", "C", "A"],
#     ["O", "G", "C", "A"]]
