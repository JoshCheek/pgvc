require 'pg_git/database'

RSpec.describe 'PgGit::Database' do
  let(:db) { PgGit::Database.new }

  describe 'schema management' do
    it 'can create and drop schemas' do
      expect(db.schema_names).to eq [:public]
      db.create_schema :othah1
      db.create_schema :othah2
      expect(db.schema_names).to eq [:public, :othah1, :othah2]
      db.drop_schema :othah1
      expect(db.schema_names).to eq [:public, :othah2]
    end
  end

  describe 'table management' do
    it 'can create a table' do
      expect { db.create_table :users, primary_key: :id, columns: %i[name] }
        .to change { db.tables.include? :users }.from(false).to(true)
    end

    it 'can drop a table' do
      db.create_table :users, primary_key: :id, columns: %i[name]
      expect { db.drop_table :users }
        .to change { db.tables.include? :users }.from(true).to(false)
    end

    it 'creates and drops the table in the public schema by default' do
      db.create_schema :other
      db.create_table :some_table
      expect(db.tables schema: :public).to include :some_table
      expect(db.tables schema: :other).to_not include :some_table
    end

    it 'can create and drop the table in another schemas' do
      db.create_schema :other
      db.create_table :some_table, schema: :other
      expect(db.tables schema: :public).to_not include :some_table
      expect(db.tables schema: :other).to include :some_table
      db.drop_table :some_table, schema: :other
      expect(db.tables schema: :public).to_not include :some_table
      expect(db.tables schema: :other).to_not include :some_table
    end
  end


  describe 'inserting rows into a table' do
    before { db.create_table :users, primary_key: :id, columns: %i[name is_admin] }

    it 'auto increments primary keys to be 1 greater than the largest primary key' do
      db.insert :users, values: {name: 'Josh', is_admin: true}
      db.insert :users, values: {name: 'Maya', is_admin: true}
      db.insert :users, values: {name: 'Bert', is_admin: true, id: 100}
      db.insert :users, values: {name: 'Sara', is_admin: true}
      expect(db.select :users).to eq [
        {id: 1,   name: 'Josh', is_admin: true},
        {id: 2,   name: 'Maya', is_admin: true},
        {id: 100, name: 'Bert', is_admin: true},
        {id: 101, name: 'Sara', is_admin: true},
      ]
    end

    it 'raises when an insert statement omits columns, except the primary key' do
      db.insert :users, values: {name: 'Josh', is_admin: true}
      expect { db.insert :users, values: {name: 'Josh'} }
        .to raise_error PgGit::Database::InvalidColumn
      expect { db.insert :users, values: {is_admin: true} }
        .to raise_error PgGit::Database::InvalidColumn
    end

    it 'raises when nonexistent columns are provided' do
      db.insert :users, values: {name: 'Josh', is_admin: true}
      expect { db.insert :users, values: {name: 'Josh', is_admin: true, other: 'whatevz'} }
        .to raise_error PgGit::Database::InvalidColumn
    end
  end

  describe 'selecting rows from a table' do
    before do
      db.create_table :users, primary_key: :id, columns: %i[name is_admin]
    end

    # database.select table_name, schema: current_branch_name
    # database.select table_name, schema: current_branch_name
    # database.select 'branches'
    # database.select('branches', where: {name: name}).any? and
    # database.insert 'branches', id: next_id!, name: name, commit_id: commit.id
    it 'can select all columns for the rows' do
      db.insert :users, values: {name: 'Josh', is_admin: true}
      expect(db.select :users).to eq [
        {id: 1, name: 'Josh', is_admin: true}
      ]
    end

    it 'can select specified columns for the rows' do
      db.insert :users, values: {name: 'Josh', is_admin: true}

      expect(db.select :users, columns: %i[id name])
        .to eq [{id: 1, name: 'Josh'}]
      expect(db.select :users, columns: %i[name is_admin])
        .to eq [{name: 'Josh', is_admin: true}]
      expect(db.select :users, columns: %i[is_admin])
        .to eq [{is_admin: true}]
    end

    it 'can filter the results with a where clause' do
      db.insert :users, values: {name: 'Josh', is_admin: true}
      db.insert :users, values: {name: 'Josh', is_admin: false}
      db.insert :users, values: {name: 'Josh', is_admin: true}
      db.insert :users, values: {name: 'Maya', is_admin: true}
      db.insert :users, values: {name: 'Maya', is_admin: false}

      expect(db.select :users, where: {name: 'noone'}).to eq []
      expect(db.select :users, where: {name: 'Josh'}).to eq [
        {id: 1, name: 'Josh', is_admin: true},
        {id: 2, name: 'Josh', is_admin: false},
        {id: 3, name: 'Josh', is_admin: true},
      ]
      expect(db.select :users, where: {name: 'Maya'}).to eq [
        {id: 4, name: 'Maya', is_admin: true},
        {id: 5, name: 'Maya', is_admin: false},
      ]
      expect(db.select :users, where: {is_admin: true}).to eq [
        {id: 1, name: 'Josh', is_admin: true},
        {id: 3, name: 'Josh', is_admin: true},
        {id: 4, name: 'Maya', is_admin: true},
      ]
      expect(db.select :users, where: {is_admin: false}).to eq [
        {id: 2, name: 'Josh', is_admin: false},
        {id: 5, name: 'Maya', is_admin: false},
      ]
    end
  end

  describe 'updating rows from a table' do
    before do
      db.create_table :users, primary_key: :id, columns: %i[name is_admin]
    end

    it 'can update specified columns' do
      db.insert :users, values: {name: 'Josh', is_admin: true}
      db.insert :users, values: {name: 'Maya', is_admin: false}
      db.insert :users, values: {name: 'Bert', is_admin: false}

      db.update :users, values: {is_admin: true}

      expect(db.select :users).to eq [
        {id: 1, name: 'Josh', is_admin: true},
        {id: 2, name: 'Maya', is_admin: true},
        {id: 3, name: 'Bert', is_admin: true},
      ]
    end


    it 'can update only rows matching a where clause' do
      db.insert :users, values: {name: 'Josh', is_admin: true}
      db.insert :users, values: {name: 'Josh', is_admin: false}
      db.insert :users, values: {name: 'Maya', is_admin: false}

      db.update :users, values: {is_admin: true}, where: {name: 'Josh'}

      expect(db.select :users).to eq [
        {id: 1, name: 'Josh', is_admin: true},
        {id: 2, name: 'Josh', is_admin: true},
        {id: 3, name: 'Maya', is_admin: false},
      ]
    end

    it 'raises when nonexistent columns are provided' do
      db.insert :users, values: {name: 'Josh', is_admin: true}
      expect { db.update :users, values: {other: 'whatevz'} }
        .to raise_error PgGit::Database::InvalidColumn
    end
  end

  describe 'deleting rows from a table' do
    # database.delete 'branches', where: {name: name}
    it 'can delete rows matching a where clause'
  end
end
