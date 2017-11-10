ENV["RACK_ENV"] = "test"
require_relative 'app'
require 'capybara'

RSpec.configure do |config|
  # config.fail_fast = true
  config.color     = true
  config.formatter = 'documentation'
end

Capybara.app = App

RSpec.describe App do
  around do |test|
    ActiveRecord::Base.transaction do
      test.call
      raise ActiveRecord::Rollback
    end
  end

  before { Capybara.reset_sessions! }
  let(:session) { Capybara.current_session }

  def visit(*args)
    session.visit(*args)
    expect(session.status_code).to eq 200
  end

  def create_product(name:, colour:)
    session.click_on 'Edit'
    expect(session.body).to_not include 'raincoat'
    session.within session.find('#new-product') do
      session.fill_in 'product[name]', with: name
      session.fill_in 'product[colour]', with: colour
      session.click_on 'Create'
    end
  end

  def login(name='Josh')
    visit '/'
    session.fill_in 'username', with: name
    session.click_on 'Login'
  end

  def create_branch(name)
    session.click_on 'Branches'
    session.fill_in 'new_branch_name', with: name
    session.click_on 'Create'
  end

  def checkout_branch(name)
    session.click_on 'Branches'
    branches = session.all '.branch'
    branch_name = branches.find { |b| b.text.include? name }
    session.within branch_name do
      session.click_on 'checkout'
    end
    assert_current_branch name
  end

  def create_and_checkout_branch(name)
    create_branch name
    checkout_branch name
  end

  def assert_current_branch(name)
    expect(session.find '.current_branch').to have_text name
  end

  describe '/reset' do
    it 'has a button to reset the database with the default branch being named "publish"' do
      visit '/'
      session.click_on 'Reset'
      Product.create! name: 'lolol'
      expect(Product.find_by name: 'lolol').to_not eq nil
      visit '/reset'
      expect(Product.find_by name: 'lolol').to eq nil
      expect(session.current_path).to eq '/'
    end
  end

  describe '/' do
    it 'lists the products on the publish branch' do
      Product.create! name: 'p1', colour: 'c1'
      Product.create! name: 'p2', colour: 'c2'
      visit '/'
      expect(session.body.scan /\b[pc]\d+\b/).to eq %w[p1 c1 p2 c2]
    end

    it 'has a login form or a logout button' do
      visit '/'
      expect(session.body).to_not include 'Josh'
      session.fill_in 'username', with: 'Josh'
      session.click_on 'Login'
      expect(session.current_path).to eq '/'
      expect(session.body).to include 'Josh'
      expect(session.body).to_not include 'Login'
      session.click_on 'Logout'
      expect(session.current_path).to eq '/'
      expect(session.body).to_not include 'Josh'
    end
  end

  describe 'branches' do
    specify 'does not show the link to non-logged-in users' do
      # This is just a demo, it's not worth trying to add proper auth
      visit '/'
      expect(session).to_not have_link 'branches'
    end

    specify 'lists the branches and has a form to create a new branch' do
      login
      session.click_on 'Branches'
      expect(session.all('.branch .name').map(&:text)).to eq ['publish']
      session.fill_in 'new_branch_name', with: 'mahbranch'
      session.click_on 'Create'
      expect(session.all('.branch .name').map(&:text).sort).to eq ['mahbranch', 'publish']
    end

    specify 'lists the branches with the user\'s current branch highlighted and a button to checkout/delete' do
      # create the branch
      login
      create_branch 'mahbranch'
      expect(session.all('.branch .name').map(&:text).sort).to eq ['mahbranch', 'publish']

      # check it out
      expect(session.find('.branch.current .name').text).to eq 'publish'
      checkout_branch 'mahbranch'
      expect(session.find('.branch.current .name').text).to eq 'mahbranch'

      # delete it
      session.within '.branch.current' do
        session.click_on 'delete'
      end
      expect(session.body).to_not include 'mahbranch'
      expect(session.find('.branch.current .name').text).to eq 'publish'
    end

    specify 'Tells you your current branch in the header' do
      login
      assert_current_branch 'publish'
      create_and_checkout_branch 'brizanch'
      assert_current_branch 'brizanch'
      checkout_branch 'publish'
      assert_current_branch 'publish'
    end
  end


  describe 'editing products' do
    it 'redirects to root, for non-logged-in users' do
      visit '/'
      expect(session).to_not have_link 'Edit'
    end

    it 'displays the products, along with a form to edit them, on the current branch' do
      boots = Product.create! name: 'boots', colour: 'green'
      login

      # Edit the boots
      session.click_on 'Edit'
      expect(session.current_path).to eq '/products'
      session.within session.find("#product-#{boots.id}") do
        session.fill_in "product[colour]", with: "black"
        session.click_on 'Update'
      end
      expect(session.current_path).to eq '/products'
      boots.reload
      expect(boots.name).to eq 'boots'
      expect(boots.colour).to eq 'black'

      # Switch branches and we shouldn't see the boots
      create_and_checkout_branch 'zomghi'

      # Now we don't see the boots (the change was not committed)
      session.click_on 'Edit'
      expect(session.body).to_not include 'boots'
    end

    xit 'allows them to be deleted on the current branch' do
      # FIXME: Need to delete
    end


    it 'has a form to create a new product on the given branch' do
      login
      create_and_checkout_branch 'bananamuffin'

      create_product name: 'raincoat', colour: 'yellow'
      expect(session.body).to include 'raincoat'

      checkout_branch 'publish'
      session.click_on 'Edit'
      expect(session.body).to_not include 'raincoat'
    end
  end


  describe 'diffing' do
    before { login }
    it 'allows you to see your working changes', t:true do
      create_product name: 'barrel', colour: 'brown'
      barrel = Product.find_by! name: 'barrel'
      session.click_on 'Diff'
      rows = session.all('.diff .row').map(&:text)
      expect(rows).to eq [
        "insert #{barrel.id} barrel brown"
      ]
    end
    it 'allows you to diff against another commit'
  end


  describe 'history' do
    it 'shows you the commits that led to your current state'
  end
end
