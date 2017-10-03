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

    def insert(name, values:, schema: :public)
      table = tables(schema: schema).fetch name
      validate_all_provided! table, values
      validate_no_extras!    table, values

      primary_key = table.fetch :primary_key
      rows        = table.fetch :rows
      max_pk = rows.map { |row| row.fetch primary_key }.max || 0
      rows << {primary_key => max_pk.succ, **values}
    end

    def select(name, where: true, columns: '*', schema: :public)
      tables(schema: schema).fetch(name).fetch(:rows)
        .select { |row| row_matches? row, where }
        .map { |row|
          next row if columns == '*'
          row.select { |column, _| columns.include? column }
        }
    end

    def update(name, values:, where: true, schema: :public)
      validate_no_extras! tables(schema: schema).fetch(name), values
      select(name, schema: schema, where: where).each do |row|
        row.merge! values
      end
    end

    def delete(name, where:, schema: :public)
      # note that this implies we need to keep track of the next primary key
      # rather than computing it, but I don't think we need that much functionality,
      # so just going ot ignore it for now :)
      table = tables(schema: schema).fetch(name)
      rows  = table.fetch :rows
      rows.reject! { |row| row_matches? row, where }
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

    def row_matches?(row, where)
      case where
      when true
        true
      when Hash
        where.all? { |column, value| row.fetch(column) == value }
      else
        raise "Wat: #{where.inspect}"
      end
    end
  end
end
