require 'pgvc/git'
require 'spec_helper'

RSpec.describe 'Mimic the git interface for familiarity' do
  include SpecHelper::Acceptance

  attr_reader :client

  before do
    @client = Pgvc.init db, system_user_ref: system_user.id, default_branch: 'master'
  end

  let(:git) { Pgvc::Git.new db }

  it 'can do a git style workflow' do
    # some local work
    db.exec "insert into products (name, colour) values ('black', 'boots')"

    # git config --global user.name 'Josh Cheek'
    git.config_user_ref 'Josh Cheek'

    # git init
    git.init

    # git add products
    git.add_table 'products'

    # git commit -m 'Add pre-existing products'
    git.commit 'Add pre-existing products'

    # git log # one commit: 'Add pre-existing products'
    messages = git.log
    expect(git.log.map(&:summary)).to eq ['Add pre-existing products']
    expect(git.log.map(&:user_ref)).to eq ['Josh Cheek']

    # git branch # 1 branch, master, which we are on
    expect(git.branch.map(&:name)).to eq ['master']
    expect(git.branch.map(&:current?)).to eq [true]

    # git branch 'add-shoes'
    git.branch 'add-shoes'

    # git branch # 2 branches, master and add-shoes, we are on master
    expect(git.branch.map(&:name)).to eq ['add-shoes', 'master']
    expect(git.branch.map(&:current?)).to eq [false, true]

    # git checkout 'add-shoes'
    git.checkout 'add-shoes'

    # git branch # 2 branches, master and add-shoes, we are on add-shoes
    expect(git.branch.map(&:name)).to eq ['add-shoes', 'master']
    expect(git.branch.map(&:current?)).to eq [true, false]

    # git log # one commit: 'Add pre-existing products'
    expect(git.log.map(&:summary)).to eq ['Add pre-existing products']
    expect(git.log.map(&:user_ref)).to eq ['Josh Cheek']

    # git diff # no changes
    # expect(git.diff).to... uhhhh...

    # insert_products shoes: 'white'
    insert_products shoes: 'white'

    # git log # one commit: 'Add pre-existing products'
    expect(git.log.map(&:summary)).to eq ['Add pre-existing products']
    expect(git.log.map(&:user_ref)).to eq ['Josh Cheek']

    # git diff # one insertion: white shoes
    # expect(git.diff).to... uhhhh...

    # git commit -m 'Add white shoes'
    git.commit 'Add white shoes'

    # git log # two commits: 'Add white shoes', 'Add pre-existing products'
    expect(git.log.map(&:summary)).to eq ['Add white shoes', 'Add pre-existing products']
    expect(git.log.map(&:user_ref)).to eq ['Josh Cheek', 'Josh Cheek']

    # git checkout master
    assert_products name: %w[boots shoes], colour: %w[bloack white]
    git.checkout 'master'
    assert_products name: %w[boots], colour: %w[bloack]

    # git log # one commit: 'Add pre-existing products'
    expect(git.log.map(&:summary)).to eq ['Add pre-existing products']
  end
end
