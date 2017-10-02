require 'pg_git/database'

RSpec.describe 'PgGit::Database' do
  describe 'table management' do
    it 'can create a table'
    it 'can drop a table'
    it 'can insert rows into a table'
  end

  describe 'inserting rows into a table' do
    it 'can insert rows when it provides a value for each column'
    it 'raises when columns are omitted'
    it 'raises when nonexistent columns are provided'
  end

  describe 'selecting rows from a table' do
    it 'can filter the results with a where clause'
    it 'can select all columns for the rows'
    it 'can select specified columns for the rows'
  end

  describe 'updating rows from a table' do
    it 'can update specified columns'
    it 'can update only rows matching a where clause'
  end

  describe 'deleting rows from a table' do
    it 'can delete rows matching a where clause'
  end
end
