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

  describe '/reset' do
    it 'resets the database with the default branch being named "publish"' do
      visit '/reset'
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
      session.fill_in 'Username', with: 'Josh'
      session.find('input[name="Login"]').click
      expect(session.current_path).to eq '/'
      expect(session.body).to include 'Josh'
      expect(session.body).to_not include 'Login'
      session.find('input[name="Logout"]').click
      expect(session.current_path).to eq '/'
      expect(session.body).to_not include 'Josh'
    end
  end

  def login(name='Josh')
    visit '/'
    session.fill_in 'Username', with: name
    session.find('input[name="Login"]').click
  end

  describe '/branches' do
    specify 'redirects to root, for non-logged-in users' do
      visit '/branches'
      expect(session.current_path).to eq '/'
    end

    specify 'lists the branches and has a form to create a new branch' do
      login
      visit '/branches'
      expect(session.all('.branch .name').map(&:text)).to eq ['publish']
      session.fill_in 'Name', with: 'mahbranch'
      session.find('input[name="Create Branch"]').click
      expect(session.all('.branch .name').map(&:text).sort).to eq ['mahbranch', 'publish']
    end

    specify 'lists the branches with the user\'s current branch highlighted and a button to checkout/delete', t:true do
      # create the branch
      login
      visit '/branches'
      session.fill_in 'Name', with: 'mahbranch'
      session.find('input[name="Create Branch"]').click
      expect(session.all('.branch .name').map(&:text).sort).to eq ['mahbranch', 'publish']

      # check it out
      expect(session.find('.branch.current .name').text).to eq 'publish'
      branches = session.all '.branch'
      mahbranch = branches.find { |b| b.text.include? 'mahbranch' }
      session.within mahbranch do
        session.click_on 'checkout'
      end
      expect(session.find('.branch.current .name').text).to eq 'mahbranch'

      # delete it
      session.within '.branch.current' do
        session.click_on 'delete'
      end
      expect(session.body).to_not include 'mahbranch'
      expect(session.find('.branch.current .name').text).to eq 'publish'
    end
  end


  xdescribe '/products' do
    describe 'GET' do
      it 'redirects to root, for non-logged-in users' do
        visit '/products'
        expect(session.current_path).to eq '/'
      end
      it 'displays the products, along with a form to edit them' do
        boots = Product.create name: 'boots', colour: 'green'
        login
        visit '/products'
        expect(session.current_path).to eq '/products'
        session.fill_in "product-#{boots.id} input[name=\"colour\"]", with: "black"
        session.find("product-#{boots.id} input[name=\"Update\"]").click
      end
      it 'has a link to create a new product'
    end
    describe 'POST' do
      it 'creates a new product on the user\'s branch'
    end
    describe 'PUT' do
      it 'updates an existing product on the user\'s branch'
    end
  end
end
