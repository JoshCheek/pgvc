pgvc (PostgreSQL version control)
=================================

* What: It's like git, but for PostgreSQL data.
* Why: My stakeholders need it.
* Should you use it: Not yet, but maybe if you contribute we can get it to a point where we can say "yes"!
* Is this a good idea: We'll find out. I'm optimistic.
* Is there any association with git: No, I mirror their interface mostly because
  I think it's explanatory and amusing.


Example
-------

See [example_git_style.rb](example_git_style.rb).
There is also an [example.rb](example.rb), but that interface is expected
to change significantly.


Getting set up for development
------------------------------

* Install and run postgresql
* Install Ruby, we use it for testing
* Install bundler, which will manage dependencies: `gem install bundler`
* Install test dependencies: `bundle install`
* Run the tests `bundle exec rspec`


Ways to contribute
------------------

* If you're interested in participating, helping to identify potential showstoppers would be great!
* If you have ideas about how to get around potential showstoppers, that would be great, too!
* We need to figure out merging
* We need a more scalable format for storing tables (maybe the way that git does arrays?)
* Anything that says "FIXME" or "TODO" in the code :)
* For the `vc` interface, I want to remove "user" from nearly every function that receives it
* There should probably be "deref" function, which takes a branch-name/branch-id/vc_hash, and
  returns its commit.
* If you know a way for me to alias the type `character (32)` as `vc_hash`, that
  would be wonderful, it feels like an implementation detail that is being scattered
  around everything that touches it.
* If you know a lot of SQL and want to code review the methods to find ways to improve them,
  that would be great.
* Is my trigger optimal? It does a "for each row", but maybe that's not a good way to do it.
* We need to figure out migrations, ie changes to a table's structure. I think you
  might be able to observe when a table changes, and then grab the code that changed it and apply
  it to the other tables, as well. We will probably need to apply it to the stored
  values, I'm thinking render them all into a table without constraints, apply them,
  then save them back into vc.rows, and updating anything that points at their value.
  Yes, this would be a change to history, but I'm comfortable with that, I don't
  have the need that git does, as all versions of the database will be stored here.
* Would it make more sense to make a schema per user rather than a schema per branch?
* Would be nice to have tags, which are like branches, except they don't get a schema,
  ie a way to name a commit
* What about makng the insertion of records into vc.rows happen on commit instead of at the time of insert?
  Or allowing them to be deferred?
