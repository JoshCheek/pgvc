# Reset the database
  require 'pg'
  PG.connect(dbname: 'postgres')
    .tap { |db| db.exec 'drop database if exists pgvc_testing' }
    .tap { |db| db.exec 'create database pgvc_testing' }
  db = PG.connect dbname: 'pgvc_testing'

# Create users and products
  db.exec <<~SQL
    SET client_min_messages=WARNING;
    create table products (
      id serial primary key,
      name varchar,
      colour varchar
    );
  SQL

# Load the lib
  $LOAD_PATH.unshift File.expand_path('lib', __dir__)
  require 'pgvc/git'
  Pgvc.init db, default_branch: 'master'

  $git = Pgvc::Git.new db

  def git
    $git
  end

# Helpers for the examples below, (for simplicity of the example, we aren't parameterising args, but don't do that for real :)
  def add_products(products)
    values = products.map { |k, v| "('#{k}', '#{v}')" }.join(', ')
    git.exec "insert into products (name, colour) values #{values}"
  end

  def delete_products(attributes)
    values = attributes.map { |name, value| "#{name} = '#{value}'" }.join(' and ')
    git.exec "delete from products where #{values}"
  end

  def update_products(attribute, updates)
    updates.each do |old, new|
      git.exec_params "update products set #{attribute} = $1 where #{attribute} = $2", [new, old]
    end
  end

  def show_products
    git.exec 'select * from products'
  end

  def fancy_diff(*args)
    git.exec("select * from git.diff(#{args.map { |a| "'#{a}'" }.join(", ")}) join vc.rows using (vc_hash) order by data")
       .map { |p| [ p.action, p.table_name, eval("{#{p.data}}").map { |k, v| [k.intern, v] }.to_h ] }
  end


# Some relevant dates
  ten_days_ago = (Date.today-10).strftime('%F')


# Some local work
  add_products "3d coyote"  => "gray", "coat"  => "navy",  "siding" => "white", "pipe" => "brass",
               "power cord" => "gray", "relay" => "black", "wire"   => "blue"


# Initialize git
  # you can make this w/e you want, eg map it to your users table's primary key
  git.config_user_ref 'system'
  git.init


# Add existing products
  git.add_table 'products'


# Normal git diff represents changes as hashes, the helper, fancy diff, shows us the values they correlate to
  git.diff.map(&:to_a)
  # => [["insert", "products", "46aa147d1c1c38ba011222c8d6d83b81"],
  #     ["insert", "products", "6bfddf27a4390073b81328afc46b2b08"],
  #     ["insert", "products", "764b1b449908d024c4eb7e8e9b6f8143"],
  #     ["insert", "products", "a21736856686c10636db8e57c5a4322c"],
  #     ["insert", "products", "b625b60c51d1e31d9b77fe96592bc168"],
  #     ["insert", "products", "e5d8c394c05e17107f74b04420d63c9f"],
  #     ["insert", "products", "e72da12427bddf4572900158f9220958"]]
  fancy_diff
  # => [["insert", "products", {:id=>"1", :name=>"3d coyote", :colour=>"gray"}],
  #     ["insert", "products", {:id=>"2", :name=>"coat", :colour=>"navy"}],
  #     ["insert", "products", {:id=>"3", :name=>"siding", :colour=>"white"}],
  #     ["insert", "products", {:id=>"4", :name=>"pipe", :colour=>"brass"}],
  #     ["insert", "products", {:id=>"5", :name=>"power cord", :colour=>"gray"}],
  #     ["insert", "products", {:id=>"6", :name=>"relay", :colour=>"black"}],
  #     ["insert", "products", {:id=>"7", :name=>"wire", :colour=>"blue"}]]
  git.commit 'Add pre-existing products'
  git.diff # => []


# Check the log history
  git.log.map { |log| [log.summary, log.user_ref] }
  # => [["Add pre-existing products", "system"]]


# Publish this data and make a branch to track that (eventually introduce tags instead)
  git.branch "publish #{ten_days_ago}"


# Import footwear
  git.config_user_ref 'Piet'
  add_products shoes: "white", boots: 'black', sandals: 'brown'
  git.commit 'Import footwear from supplier'


# No uncommitted changes, but we can see them if we diff from the last publish
  fancy_diff # => []
  fancy_diff "publish #{ten_days_ago}"
  # => [["insert", "products", {:id=>"10", :name=>"sandals", :colour=>"brown"}],
  #     ["insert", "products", {:id=>"8", :name=>"shoes", :colour=>"white"}],
  #     ["insert", "products", {:id=>"9", :name=>"boots", :colour=>"black"}]]


# Maggie realizes that the 3D Coyote is actually a 2D Coyote
  git.config_user_ref 'Maggie'
  update_products :name, '3d coyote' => '2d coyote'
  show_products.map(&:name)
  git.commit 'Fix "2d coyote", which was mislabeled as "3d coyote"'


# Another publish
  git.branch "publish #{(Date.today-5).strftime('%F')}"


# Delete boots
  git.config_user_ref 'System'
  delete_products name: 'coat'
  git.commit 'Delete products removed from feed'


# Another publish
  git.branch "publish #{(Date.today-4).strftime('%F')}"


# Check the log
  git.log.map { |l| [l.user_ref, l.summary] }
  # => [["System", "Delete products removed from feed"],
  #     ["Maggie", "Fix \"2d coyote\", which was mislabeled as \"3d coyote\""],
  #     ["Piet", "Import footwear from supplier"],
  #     ["system", "Add pre-existing products"]]


# Check the branches
  git.branch.map { |b| [b.current?, b.name] }
  # => [[true, "master"],
  #     [false, "publish 2017-10-21"],
  #     [false, "publish 2017-10-26"],
  #     [false, "publish 2017-10-27"]]


# Now Gordana starts a long running change, lets do it on a branch
  git.config_user_ref 'Gordana'
  git.branch 'Electrical Review'
  git.checkout 'Electrical Review'
  git.branch.map { |b| [b.current?, b.name] }
  # => [[true, "Electrical Review"],
  #     [false, "master"],
  #     [false, "publish 2017-10-21"],
  #     [false, "publish 2017-10-26"],
  #     [false, "publish 2017-10-27"]]


# Gordana updates the names to be capitalized
  update_products :name, 'power cord' => 'Power Cord'
  fancy_diff
  # => [["insert", "products", {:id=>"5", :name=>"Power Cord", :colour=>"gray"}],
  #     ["delete", "products", {:id=>"5", :name=>"power cord", :colour=>"gray"}]]
  git.commit 'Electrical Review: Capitalize name for "Power cord"'


# How is that different from what is on the master branch?
  fancy_diff 'master'
  # => [["insert", "products", {:id=>"5", :name=>"Power Cord", :colour=>"gray"}],
  #     ["delete", "products", {:id=>"5", :name=>"power cord", :colour=>"gray"}]]


# Meanwhile, Ji-Sook wants to do a change for ICM, she's on the "master" branch and can't see Gordana's changes
  git.config_user_ref 'Ji-Sook'
  git.branch.map { |b| [b.current?, b.name] }
  # => [[false, "Electrical Review"],
  #     [true, "master"],
  #     [false, "publish 2017-10-21"],
  #     [false, "publish 2017-10-26"],
  #     [false, "publish 2017-10-27"]]


# She checks out the branch and updates the boots from brown to tan
  git.branch 'ICM-997'
  git.checkout 'ICM-997'
  update_products :colour, brown: 'tan'
  fancy_diff
  # => [["delete", "products", {:id=>"10", :name=>"sandals", :colour=>"brown"}],
  #     ["insert", "products", {:id=>"10", :name=>"sandals", :colour=>"tan"}]]
  git.commit 'ICM-997 fix colour of the sandals'


# She doesn't see Gordana's changes because she branched off of "master", not "Electrical Review"
  git.log.map { |l| [l.user_ref, l.summary] }
  # => [["Ji-Sook", "ICM-997 fix colour of the sandals"],
  #     ["System", "Delete products removed from feed"],
  #     ["Maggie", "Fix \"2d coyote\", which was mislabeled as \"3d coyote\""],
  #     ["Piet", "Import footwear from supplier"],
  #     ["system", "Add pre-existing products"]]


# What has she changed as compared to what is published?
  fancy_diff 'master'
  # => [["delete", "products", {:id=>"10", :name=>"sandals", :colour=>"brown"}],
  #     ["insert", "products", {:id=>"10", :name=>"sandals", :colour=>"tan"}]]


# What has she changed as compared to Gordana's "Electrical Review"?
  fancy_diff 'Electrical Review'
  # => [["delete", "products", {:id=>"10", :name=>"sandals", :colour=>"brown"}],
  #     ["insert", "products", {:id=>"10", :name=>"sandals", :colour=>"tan"}],
  #     ["delete", "products", {:id=>"5", :name=>"Power Cord", :colour=>"gray"}],
  #     ["insert", "products", {:id=>"5", :name=>"power cord", :colour=>"gray"}]]


# Ji-Sook merges her change into the master branch
  git.checkout 'master'
  git.log.map { |l| [l.user_ref, l.summary] }
  # => [["System", "Delete products removed from feed"],
  #     ["Maggie", "Fix \"2d coyote\", which was mislabeled as \"3d coyote\""],
  #     ["Piet", "Import footwear from supplier"],
  #     ["system", "Add pre-existing products"]]



# ...AAAAAND THIS IS HOW FAR WE CURRENTLY ARE :P
  git.merge 'ICM-997' # ~> PG::UniqueViolation: ERROR:  duplicate key value violates unique constraint "products_pkey"\nDETAIL:  Key (id)=(10) already exists.\nCONTEXT:  SQL statement " insert into products select vc_record.*\n               from populate_record(null::products, $1) as vc_record\n            "\nPL/pgSQL function git.merge(character varying) line 31 at EXECUTE\n
  git.log.map { |l| [l.user_ref, l.summary] }
  # =>

# ~> PG::UniqueViolation
# ~> ERROR:  duplicate key value violates unique constraint "products_pkey"
# ~> DETAIL:  Key (id)=(10) already exists.
# ~> CONTEXT:  SQL statement " insert into products select vc_record.*
# ~>                from populate_record(null::products, $1) as vc_record
# ~>             "
# ~> PL/pgSQL function git.merge(character varying) line 31 at EXECUTE
# ~>
# ~> /Users/xjxc322/code/pgvc/lib/pgvc/git.rb:60:in `exec_params'
# ~> /Users/xjxc322/code/pgvc/lib/pgvc/git.rb:60:in `exec_params'
# ~> /Users/xjxc322/code/pgvc/lib/pgvc/git.rb:48:in `fn'
# ~> /Users/xjxc322/code/pgvc/lib/pgvc/git.rb:42:in `merge'
# ~> /Users/xjxc322/code/pgvc/example_git_style.rb:193:in `<main>'
