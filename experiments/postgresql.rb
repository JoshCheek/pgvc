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
  CREATE TABLE chars (
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
        -- GROUP BY crnt.parent_id
      )--,

      -- unique_ancestors (depth, id) AS (
      --   SELECT min(depth), id
      --   FROM ancestors
      --   GROUP BY id
      -- )

    SELECT depth, chars.*
    FROM ancestors a
    JOIN chars ON (chars.id = a.id)
    ORDER BY a.depth; -- add DESC to get the path from the root to the node in question
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
  db.exec_params "INSERT INTO chars (val) VALUES ($1)", [char_for(i)]
  next if i == 1 # first char, "A", has no parent
  db.exec_params "INSERT INTO ancestry (parent_id, child_id) VALUES ($1, $2)", [i/2, i]
end

# Validate
db.exec('SELECT * FROM chars;').values.map(&:join).join(" ")
# => "1A 2B 3C 4D 5E 6F 7G 8H 9I 10J 11K 12L 13M 14N 15O"

db.exec(<<-SQL).values.map(&:join).join(" ")
  SELECT chars.* FROM chars
  JOIN ancestry ON (chars.id = ancestry.child_id)
  WHERE ancestry.parent_id = 6 -- "F"'s children are "L" and "M"
SQL
# => "12L 13M"

# Get the hierarchy of each character
db.exec('SELECT * FROM chars;').map do |result|
  id = result.fetch 'id'
  find_ancestors(db, id).map(&:values).map(&:last).join(" ")
end
# => ["A",
#     "B A",
#     "C A",
#     "D B A",
#     "E B A",
#     "F C A",
#     "G C A",
#     "H D B A",
#     "I D B A",
#     "J E B A",
#     "K E B A",
#     "L F C A",
#     "M F C A",
#     "N G C A",
#     "O G C A"]

# Multiple parents:
#               1A
#       2B              3C
#   4D     5E        6F       7G
# 8H 9I  10J 11K   12L 13M  14N 15O
# Additionally:
#   L will have parent E
#   F will have a parent H
# expected ancestry: L (F E) (C B H) (D A)  ...is this right? can there be conflicts?
l, e, f, h = 12, 5, 6, 8
db.exec_params "INSERT INTO ancestry (parent_id, child_id) VALUES ($1, $2), ($3, $4)",
                                                                  [ e,  l,    h,  f]
find_ancestors(db, 12) # L
  .map(&:values) # => [["0", "12", "L"], ["1", "6", "F"], ["1", "5", "E"], ["2", "2", "B"], ["2", "3", "C"], ["2", "8", "H"], ["3", "1", "A"], ["3", "1", "A"], ["3", "4", "D"], ["4", "2", "B"], ["5", "1", "A"]]
  .group_by(&:first)
  .map { |k, vs|  [k, vs.map(&:last)] }
  .to_h
# => {"0"=>["L"],
#     "1"=>["F", "E"],
#     "2"=>["B", "C", "H"],
#     "3"=>["A", "A", "D"],
#     "4"=>["B"],
#     "5"=>["A"]}
