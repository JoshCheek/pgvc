require 'pg'
db = PG.connect dbname: 'josh_testing'
db.exec 'begin' # discards changes
def db.exec(*)
  super.to_a
end

# %1$s references arg in position 1
(db.exec <<~SQL
  select * from format(
    '%s   %1$s',
    'o m g'
  )
  SQL
)     # => [{"format"=>"o m g   o m g"}]
.uniq # => [{"format"=>"o m g   o m g"}]


# %I identity-quotes the arg in that position
(db.exec <<~SQL
  select * from format('%s', quote_ident('o m g'))
  union all
  select * from format('%I', 'o m g')
  SQL
)     # => [{"format"=>"\"o m g\""}, {"format"=>"\"o m g\""}]
.uniq # => [{"format"=>"\"o m g\""}]


# %L literal-quotes the arg in that position
(db.exec <<~SQL
  select * from format('%s', quote_literal('o m g'))
  union all
  select * from format('%L', 'o m g')
  SQL
)     # => [{"format"=>"'o m g'"}, {"format"=>"'o m g'"}]
.uniq # => [{"format"=>"'o m g'"}]
