require 'pgvc/git'
require 'spec_helper'

RSpec.describe 'Mimic the git interface for familiarity' do
  include SpecHelper::Acceptance

  attr_reader :client

  before do
    @client = Pgvc.init db, system_user_ref: 'system', default_branch: 'master'
  end

  let(:git) { Pgvc::Git.new db }

  it 'can do a git style workflow' do
    # some local work
    git.exec "insert into products (name, colour) values ('boots', 'black')"

    # git config --global user.name 'Josh Cheek'
    git.config_user_ref 'Josh Cheek'

    # git init
    git.init

    # git branch
    git.branch 'pristine branch'

    # git add products
    git.add_table 'products'
    boots = git.exec('select * from products').first

    # git commit -m 'Add pre-existing products'
    commit1 = git.commit 'Add pre-existing products'

    # git log # one commit: 'Add pre-existing products'
    messages = git.log
    expect(git.log.map(&:summary)).to eq ['Add pre-existing products', 'Initial commit']
    expect(git.log.map(&:user_ref)).to eq ['Josh Cheek', 'system']

    # git branch # 2 branches, *master, and "pristine shoes"
    expect(git.branch.map(&:name)).to eq ['master', 'pristine branch']
    expect(git.branch.map(&:current?)).to eq [true, false]

    # git branch 'add-shoes'
    git.branch 'add-shoes'

    # git branch # 3 branches, "pristine branch", *master, and add-shoes
    expect(git.branch.map(&:name)).to eq ['add-shoes', 'master', 'pristine branch']
    expect(git.branch.map(&:current?)).to eq [false, true, false]

    # git checkout 'add-shoes'
    git.checkout 'add-shoes'

    # git branch # 2 branches, master and add-shoes, we are on add-shoes
    expect(git.branch.map(&:name)).to eq ['add-shoes', 'master', 'pristine branch']
    expect(git.branch.map(&:current?)).to eq [true, false, false]

    # git log # one commit: 'Add pre-existing products'
    expect(git.log.map(&:summary)).to eq ['Add pre-existing products', 'Initial commit']
    expect(git.log.map(&:user_ref)).to eq ['Josh Cheek', 'system']

    # git diff # no changes
    expect(git.diff).to eq []

    # insert_products shoes: 'white'
    shoes = git.exec("insert into products (name, colour) values ('shoes', 'white') returning *").first

    # git log # one commit: 'Add pre-existing products'
    expect(git.log.map(&:summary)).to eq ['Add pre-existing products', 'Initial commit']
    expect(git.log.map(&:user_ref)).to eq ['Josh Cheek', 'system']

    # git diff # one insertion: white shoes
    diff1 = git.diff
    expect(diff1.map(&:action)).to eq ['insert']
    expect(diff1.map(&:table_name)).to eq ['products']
    expect(diff1.map(&:vc_hash)).to eq [shoes.vc_hash]

    # git commit -m 'Add white shoes'
    commit2 = git.commit 'Add white shoes'

    # git diff # no uncommitted changes
    expect(git.diff).to eq []

    # git diff HEAD^ # one insertion: white shoes
    expect(git.diff commit1.vc_hash).to eq diff1

    # git log # two commits: 'Add white shoes', 'Add pre-existing products'
    expect(git.log.map(&:summary)).to eq ['Add white shoes', 'Add pre-existing products', 'Initial commit']
    expect(git.log.map(&:user_ref)).to eq ['Josh Cheek', 'Josh Cheek', 'system']

    # git checkout master
    products = git.exec('select * from products order by id')
    expect(products.map(&:name)).to eq %w[boots shoes]
    expect(products.map(&:colour)).to eq %w[black white]
    git.checkout 'master'
    products = git.exec('select * from products order by id')
    expect(products.map(&:name)).to eq %w[boots]
    expect(products.map(&:colour)).to eq %w[black]

    # git log # one commit: 'Add pre-existing products'
    expect(git.log.map(&:summary)).to eq ['Add pre-existing products', 'Initial commit']

    # git checkout HEAD^
    git.checkout 'pristine branch'
    expect(git.log.map &:summary).to eq ['Initial commit']

    # git diff add-shoes # inverse of previous diff
    diff2 = git.diff 'add-shoes'
    expect(diff2.map &:to_h).to eq [
      {action: 'delete', table_name: 'products', vc_hash: shoes.vc_hash},
      {action: 'delete', table_name: 'products', vc_hash: boots.vc_hash},
    ]
  end


  it 'has git style errors' do
    git.config_user_ref 'Josh Cheek'

    # branch
    git.branch('b1')
    expect { git.branch('b1') }.to raise_error PG::UniqueViolation, /A branch named 'b1' already exists/

    # checkout
    expect { git.checkout('dne') }.to raise_error PG::NoDataFound, /'dne' did not match any branches known to pgvc/
  end


  describe 'merging', t:true do
    before do
      git.config_user_ref 'Josh Cheek'
      git.init
      git.add_table 'products'
      git.exec "insert into products (name, colour) values ('boots', 'black')"
      git.commit 'Add pre-existing products'
    end

    describe 'without conflicts' do
      it 'can fast forward merge' do
        git.branch 'add-boots'
        git.checkout 'add-boots'
        git.exec "delete from products"
        git.exec "insert into products (name, colour) values ('white', 'shoes')"
        git.commit 'delete boots, add shoes'
        log      = git.log
        products = git.exec 'select * from products'
        git.checkout 'master'
        expect(git.log).to_not eq log
        expect(git.exec 'select * from products').to_not eq products
        git.merge 'add-boots'
        expect(git.log).to eq log
        expect(git.exec 'select * from products').to eq products
      end

      it 'can do a merge when there are no conflicts'
    end
  end
end
