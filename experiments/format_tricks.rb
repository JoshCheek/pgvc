require 'pg'
PG.connect(dbname: 'josh_testing').exec(<<~SQL).to_a
  begin;

  select * from format(
    -- %1$s references arg in position 1
    '1 (%s) (%1$s)',
    'o m g'
  ) union select * from format(
    -- %I auto-quotes the arg in that position
    '2 (%s) (%I)',
    quote_ident('o m g'),
    'o m g'
  ) order by format;
  SQL
  # => [{"format"=>"1 (o m g) (o m g)"}, {"format"=>"2 (\"o m g\") (\"o m g\")"}]
