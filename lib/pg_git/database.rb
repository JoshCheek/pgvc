class PgGit
  class Database
    InvalidInsertion = Class.new StandardError

    def initialize
      self.schemas = {
        public: { tables: {} }
      }
    end

    def tables
      schemas[:public][:tables]
    end

    def create_table(name, primary_key:, columns:)
      tables[name] = {
        primary_key: primary_key,
        columns:     columns,
        rows:        [],
      }
    end

    def drop_table(name)
      tables.delete name
    end

    def insert(name, values:)
      table       = tables.fetch name
      primary_key = table.fetch :primary_key
      columns     = table.fetch :columns
      rows        = table.fetch :rows

      columns.each do |column|
        next if values.key? column
        raise InvalidInsertion, "#{name.inspect} expects #{columns.inspect}, but was missing #{column.inspect}"
      end

      values.each do |column, value|
        next if columns.include? column
        next if primary_key == column
        raise InvalidInsertion, "#{name.inspect} expects #{columns.inspect}, but was given #{column.inspect}"
      end

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

    private

    attr_accessor :schemas
  end
end
