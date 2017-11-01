ENV["RACK_ENV"] = "test"
require_relative 'app'
require 'capybara'

RSpec.configure do |config|
  config.fail_fast = true
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
      expect(session.body).to_not include 'Josh'
    end
  end

  describe '/products' do
    describe 'GET' do
      it 'redirects to root, for non-logged-in users'
      it 'displays the products, along with a form to edit them'
      it 'has a link to create a new product'
    end
    describe 'POST' do
      it 'creates a new product on the user\'s branch'
    end
    describe 'PUT' do
      it 'updates an existing product on the user\'s branch'
    end
  end

  describe '/branches' do
    specify 'GET lists the branches with the user\'s current branch highlighted'
    specify 'POST creates a branch'
    specify 'DELETE deletes a branch'
  end

  describe '/branch' do
    specify 'POST checks out a branch'
  end
end
