# require 'pgvc/git'
# require 'spec_helper'

# RSpec.describe 'Mimic the git interface for familiarity' do
#   include SpecHelper::Acceptance

#   def before_init
#     insert_products boots: 'black'
#     super
#   end

#   xit 'can do a git style workflow' do
#     git config --global user.name 'Josh Cheek'
#     git config --global user.email 'josh.cheek@gmail.com'
#     git init
#     git commit -m 'Add pre-existing products'
#     git log # one commit: 'Add pre-existing products'
#     git branch # 1 branch, master, which we are on
#     git branch 'add-shoes'
#     git branch # 2 branches, master and add-shoes, we are on master
#     git checkout 'add-shoes'
#     git branch # 2 branches, master and add-shoes, we are on add-shoes
#     git log # one commit: 'Add pre-existing products'
#     insert_products shoes: 'white'
#     git log # one commit: 'Add pre-existing products'
#     git diff # one insertion: white shoes
#     git commit -m 'Add white shoes'
#     git log # two commits: 'Add white shoes', 'Add pre-existing products'
#     assert_products name: %w[boots shoes], colour: %w[bloack white]
#     git checkout master
#     assert_products name: %w[boots], colour: %w[bloack]
#     git log # one commit: 'Add pre-existing products'
#   end
# end
