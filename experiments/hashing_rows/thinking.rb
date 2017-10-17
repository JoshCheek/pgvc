# Okay:
# Assume that we have a function, h, which can take an arbitrary value and return
# a hash for it (md5, probably, b/c that's built into postgresql)
#
# Assume we have this additional table:
# ```sql
# create table uncommitted_rows (
#   table_name character variable,
#   row_hash character(32), -- 32 b/c thats how many characters are in an md5 hash
#   row_data hstore (or JSON?)
# );
# ```
#
# Assume that for each type that our system stores, we have a table:
# ```sql
# create table <TYPE>_values (
#   hash character(32),
#   value <TYPE>
# );
# ```
#
# Let "MT" represent a table that is modified, which we want to track changes to.
# Let "MR" represent a row that is modified (created, deleted, updated).
# Let "UT" represent the table `uncommitted_rows`
# Let "UR" represent a row that is added to UT to track MR
#
# Add a trigger to MT to observe changes to its rows. When we see that change,
# MR, create UR and save it into UT. UR's `table_name` is MT's name, its
# `row_hash` is `h(UR.row_data)`, its `row_data` is (in Ruby here, b/c IDK how
# to write it in SQL) `MR.to_h.map { |k, v| [k, h(v)] }.to_h`
#
# (WHAT DO WE DO FOR DELETION?)
#
# Additionally, for each of its values, save them into their associated type's
# values table, that way we can look them up via the hashes stored in `UR.row_data`
#
# When we decide to make a commit for our database:
# for each `table_name` in `uncommitted_rows`:
#   ...


# -----------
# Scratch the above (kinda). Add a `version_control_hash` column to each table
# we want to track, for each insertion or deletion, calculate the `uncommitted_rows`
# row above, and save that into `version_control_rows` (same structure as `uncommitted_rows`)
# and save the hash on the row. From the row, its hash should always be correct,
# so it serves as a cache so that we don't have to rehash every row. From that
# hash, the row can always be rebuilt by looking it pu in `version_control_rows`.

# ```ruby
def commit_database
  tables = @version_controlled_tables.map do |table|
    [table.name, commit_table(table)]
  end.to_h
  db = VC::Database.find_or_create_by tables: tables, hash: h(table_hashes)
  @branch.update! hash: db.hash
end


ROW_GROUP_SIZE = 32
def commit_table(table)
  # for efficiency, rows are already committed by the trigger
  row_hashes = table.rows.map(&:hash)
  rows_depth = 0

  group_hashes = row_hashes.each_slice(ROW_GROUP_SIZE).map do |slice|
    attrs = { row_hashes: slice, hash: h(slice) }
    VC::RowGroup.find_or_create_by(attrs).hash
  end

  while group_hashes.length > 1
    rows_depth += 1
    group_hashes = group_hashes.each_slice(ROW_GROUP_SIZE).map do |slice|
      attrs = { group_hashes: slice, hash: h(slice) }
      VC::RowGroupGroup.find_or_create_by(attrs).hash
    end
  end

  rows_hash = group_hashes.first
  VC::Table.find_or_create_by!(
    rows_hash:   rows_hash,
    rows_depth:  rows_depth,
    column_hash: table.columns_hash
  )
end

# ```
#
# -----
# Then, to create a branch:
# ```ruby
def create_branch(branch_name, hash)
  database = VC::Database.find_by(hash: hash)
  branch   = VC::Branch.create! name: name, hash: hash do |branch|
    branch.schema_name = "branch_#{branch.id}_#{branch.name.normalize}"
  end
  schema = Schema.create! name: branch.schema_name

  @current_schema = schema

  database.table_hashes.each do |name, hash|
    create_table schema, name, hash
  end
end

def create_table(schema, name, hash)
  vc_table = VC::Table.find_by! hash: hash
  columns  = VC::Columns.find_by! hash: vc_table.columns_hash
  table    = Table.create! schema: schema, name: name, columns: columns

  insert_rows table, columns, vc_table.rows_hash, vc_table.rows_depth
end

def insert_rows(table, columns, root_hash, depth)
  if depth.zero?
    VC::RowGroup.find_by!(hash: root_hash).row_hashes.each do |hash|
      row = VC::Row.find_by! hash: hash
      row_data = row.row_data.map do |name, value_hash|
        type  = columns[name]
        value = VC.const_get("#{type.name}Values").find_by(hash: value_hash).value
        [name, value]
      end.to_h
      table.insert! row_data
    end
  else
    VC::RowGroupGroup
      .find_by!(hash: root_hash)
      .group_hashes
      .each { |hash| insert_rows table, hash, depth-1 }
  end
end
