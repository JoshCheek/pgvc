class PgGit
  class Database
    InvalidColumn = Class.new StandardError

    def initialize
      self.schemas = {}
      create_schema :public
    end

    def create_schema(name)
      schemas[name] = { tables: {} }
    end

    def drop_schema(name)
      schemas.delete name
    end

    def schema_names
      schemas.keys
    end

    def tables(schema: :public)
      schemas.fetch(schema).fetch(:tables)
    end

    def create_table(name, schema: :public, primary_key: nil, columns: [])
      tables(schema: schema)[name] = {
        name:        name,
        primary_key: primary_key,
        columns:     columns,
        rows:        [],
      }
    end

    def drop_table(name, schema: :public)
      tables(schema: schema).delete name
    end

    def insert(name, values:)
      table = tables.fetch name
      validate_all_provided! table, values
      validate_no_extras!    table, values

      primary_key = table.fetch :primary_key
      rows        = table.fetch :rows
      max_pk = rows.map { |row| row.fetch primary_key }.max || 0
      rows << {primary_key => max_pk.succ, **values}
    end

    def select(name, where: true, columns: '*')
      tables.fetch(name).fetch(:rows).select do |row|
        case where
        when true
          true
        when Hash
          where.all? do |column, value|
            row.fetch(column) == value
          end
        else
          raise "Wat: #{where.inspect}"
        end
      end.map do |row|
        next row if columns == '*'
        row.select { |column, _| columns.include? column }
      end
    end

    def update(name, values:, where: true)
      validate_no_extras!  tables.fetch(name), values
      select(name, where: where).each do |row|
        row.merge! values
      end
    end

    private

    attr_accessor :schemas

    def validate_all_provided!(table, values)
      name    = table.fetch :name
      columns = table.fetch(:columns)
      columns.each do |column|
        next if values.key? column
        raise InvalidColumn, "#{name.inspect} expects #{columns.inspect}, but was missing #{column.inspect}"
      end
    end

    def validate_no_extras!(table, values)
      name        = table.fetch :name
      columns     = table.fetch :columns
      primary_key = table.fetch :primary_key
      values.each do |column, value|
        next if columns.include? column
        next if primary_key == column
        raise InvalidColumn, "#{name.inspect} expects #{columns.inspect}, but was given #{column.inspect}"
      end
    end
  end
end
