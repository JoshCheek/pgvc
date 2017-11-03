require 'pg'

db = PG.connect(dbname: 'josh_testing')
db.exec 'begin' # discard changes
def db.exec(*)
  super.to_a
end

db.exec <<~SQL
  -- start at 1000, end at 2000, iterate by 100
  select * from generate_series(1000, 2000, 100)
  SQL
  # => [{"generate_series"=>"1000"},
  #     {"generate_series"=>"1100"},
  #     {"generate_series"=>"1200"},
  #     {"generate_series"=>"1300"},
  #     {"generate_series"=>"1400"},
  #     {"generate_series"=>"1500"},
  #     {"generate_series"=>"1600"},
  #     {"generate_series"=>"1700"},
  #     {"generate_series"=>"1800"},
  #     {"generate_series"=>"1900"},
  #     {"generate_series"=>"2000"}]
