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

  describe '/reset' do
    it 'resets the database with the default branch being named "publish"' do
      session.visit '/reset'
      expect(session.status_code).to eq 200
      Product.create! name: 'lolol'
      expect(Product.find_by name: 'lolol').to_not eq nil
      session.visit '/reset'
      expect(session.status_code).to eq 200
      expect(Product.find_by name: 'lolol').to eq nil
    end
  end

  describe '/' do
    it 'lists the products on the publish branch'
    it 'has a login form'
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

  describe '/session' do
    specify 'POST logs in'
    specify 'DELETE logs out'
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
