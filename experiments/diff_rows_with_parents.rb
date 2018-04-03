require 'pg'
db = PG.connect dbname: 'josh_testing'
db.exec 'begin'
def db.exec(*)
  super.to_a
end
def db.exec_params(*)
  super.to_a
end
# db.exec 'create extension hstore;'


# ===== SEED =====
db.exec <<~SQL
create table parent (id serial primary key, val text);
create table child1   (id serial primary key, val text);
create table child2  (id serial primary key, val text);
insert into parent (id, val)
  values (1, 'unchanged'),
         (2, 'deleted-child1'),
         (3, 'deleted-child2'),
         (4, 'modified-child1'),
         (5, 'modified-child2'),
         (6, 'modified-both');
insert into child1 (id, val)
 values (1, 'unchanged'),
        (3, 'deleted-child2'),
        (4, 'modified-child1-(1)'),
        (5, 'modified-child2'),
        (6, 'modified-both-(1)'),
        (7, 'inserted-child1');
insert into child2 (id, val)
  values (1, 'unchanged'),
         (2, 'deleted-child1'),
         (4, 'modified-child1'),
         (5, 'modified-child2-(2)'),
         (6, 'modified-both-(2)'),
         (8, 'inserted-child2');
SQL

rows = db.exec(<<~SQL).map { |row| row.values.map &:inspect }
  select coalesce(parent.id, child1.id, child2.id) as id,
         parent.val as parent_val,
         child1.val as child1_val,
         child2.val as child2_val
  from parent
  full join child1 using (id)
  full join child2 using (id)
  where child1 is distinct from child2
SQL

format = rows.transpose
             .map { |col| col.map(&:length).max }
             .map { |n| "%-#{n}s" }.join("  ")

rows.each { |row| puts format % row }

# -- id - parent ----------- child 1 -------------- child 2 -------------

# >> "2"  "deleted-child1"   nil                    "deleted-child1"
# >> "3"  "deleted-child2"   "deleted-child2"       nil
# >> "4"  "modified-child1"  "modified-child1-(1)"  "modified-child1"
# >> "5"  "modified-child2"  "modified-child2"      "modified-child2-(2)"
# >> "6"  "modified-both"    "modified-both-(1)"    "modified-both-(2)"
# >> "7"  nil                "inserted-child1"      nil
# >> "8"  nil                nil                    "inserted-child2"
