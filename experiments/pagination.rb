# https://www.citusdata.com/blog/2016/03/30/five-ways-to-paginate/
require 'pg'

PG.connect(dbname: 'postgres')
  .tap { |pg| pg.exec('drop database josh_testing') }
  .tap { |pg| pg.exec('create database josh_testing') }

db = PG.connect(dbname: 'josh_testing')

db.exec <<~SQL
  create table medley as
    select
      generate_series(1,100000) as n,
      substr(
        concat(
          md5(random()::text),
          md5(random()::text)
        ),
        1,
        (random() * 64)::integer + 1
      ) as description;
  SQL


# Notify query planner of drastically changed table size
db.exec 'vacuum analyze'


# =====  Pagination via limit+offset is linearly expensive  =====
  0.step(by: 5000, to: 50_000).map do |i|
    result = db.exec("explain analyze select * from medley limit 5000 offset #{i}").to_a
    "Offset: " + i.to_s.rjust(5, '0') + ", " + result.last['QUERY PLAN']
  end
  # => ["Offset: 00000, Execution time: 1.060 ms",
  #     "Offset: 05000, Execution time: 1.604 ms",
  #     "Offset: 10000, Execution time: 2.142 ms",
  #     "Offset: 15000, Execution time: 2.744 ms",
  #     "Offset: 20000, Execution time: 3.399 ms",
  #     "Offset: 25000, Execution time: 3.874 ms",
  #     "Offset: 30000, Execution time: 4.347 ms",
  #     "Offset: 35000, Execution time: 4.969 ms",
  #     "Offset: 40000, Execution time: 5.499 ms",
  #     "Offset: 45000, Execution time: 6.094 ms",
  #     "Offset: 50000, Execution time: 6.751 ms"]



# =====  Pagination via a cursor is constant-time expensive =====
  # NOTE: Measure from Ruby b/c "explain analyze" doesn't work on "fetch", this
  # means the value is not directly comparable to the limit+offset approach above
  db.exec "begin"

  # Get a cursor to the query
  db.exec "declare medley_cur cursor for select * from medley"

  0.step(by: 5000, to: 50_000).map do |i|
    start_time = Time.now
    result     = db.exec 'fetch 5000 from medley_cur'
    end_time   = Time.now
    seconds    = end_time - start_time
    "Offset: " + i.to_s.rjust(5, '0') + ", Execution time: %.3f ms" % (seconds*1000)
  end
  # => ["Offset: 00000, Execution time: 2.341 ms",
  #     "Offset: 05000, Execution time: 2.118 ms",
  #     "Offset: 10000, Execution time: 1.974 ms",
  #     "Offset: 15000, Execution time: 1.726 ms",
  #     "Offset: 20000, Execution time: 1.946 ms",
  #     "Offset: 25000, Execution time: 2.540 ms",
  #     "Offset: 30000, Execution time: 2.407 ms",
  #     "Offset: 35000, Execution time: 1.850 ms",
  #     "Offset: 40000, Execution time: 1.826 ms",
  #     "Offset: 45000, Execution time: 1.692 ms",
  #     "Offset: 50000, Execution time: 1.919 ms"]

  db.exec 'end'


# =====  Keyset Pagination  =====
  # Skipping b/c it's not general enough for my current needs, but it does have
  # some nice characteristics, worth looking into again next time I need pagination



# =====  Clustered TID Scan  =====
  # NOTE: While incredibly interesting, this feels too fragile to depend on,
  # and I don't need random access anyway, and I'm going to hold an open
  # transaction, anyway, so this is really just for curiousity's sake.

  # ctids are implicitly stored on every row and have the form (page, row)
  # where "page" is a file-system page (I think), so it's like a map to the
  # row's location on the file-system. Apparently this is what indexes use.
  db.exec("select ctid, n from medley order by n limit 5").to_a
  # => [{"ctid"=>"(0,1)", "n"=>"1"},
  #     {"ctid"=>"(0,2)", "n"=>"2"},
  #     {"ctid"=>"(0,3)", "n"=>"3"},
  #     {"ctid"=>"(0,4)", "n"=>"4"},
  #     {"ctid"=>"(0,5)", "n"=>"5"}]

  # We can change the order with the "cluster" command:
  db.exec "create index description_idx on medley using btree (description)"
  db.exec "cluster medley using description_idx"

  # Now the ctids match the description instead
  db.exec('select ctid, n from medley order by n limit 5').to_a
  # => [{"ctid"=>"(345,34)", "n"=>"1"},
  #     {"ctid"=>"(328,78)", "n"=>"2"},
  #     {"ctid"=>"(28,63)", "n"=>"3"},
  #     {"ctid"=>"(798,37)", "n"=>"4"},
  #     {"ctid"=>"(563,63)", "n"=>"5"}]
  db.exec('select ctid, description from medley order by description limit 5').to_a
  # => [{"ctid"=>"(0,1)", "description"=>"0"},
  #     {"ctid"=>"(0,2)", "description"=>"0"},
  #     {"ctid"=>"(0,3)", "description"=>"0"},
  #     {"ctid"=>"(0,4)", "description"=>"0"},
  #     {"ctid"=>"(0,5)", "description"=>"0"}]


# =====  Keyset with Estimated Bookmarks  =====
  # Jesus, this author, Joe Nelson, knows his shit! I'm not going to try to
  # reproduce it right now, but he looks at pg's internal statistical data to
  # figure out where the page is.
