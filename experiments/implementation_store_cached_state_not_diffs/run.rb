require_relative 'helpers'

db = Database.new 'pg_git', reset: true

db.exec 'select complete_commit();'
db.all 'select * from table_hashes;'
# => [#<Result hash="d12dbd12d53ce0febf63eb41c5091a36" name="table1">,
#     #<Result hash="072db2056ea084a77ec21dc70a5ddebe" name="table2">]

db.all 'select * from database_hashes;'
# => [#<Result hash="1b21eae2e59aa204a3fe03847382beed">]
