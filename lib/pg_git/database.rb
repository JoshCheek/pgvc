class PgGit
  class Database
    def initialize
      self.schemas = {public: {tables: {}}}
    end

    def tables
      schemas[:public][:tables]
    end

    def create_table(name, primary_key:, columns:)
      schemas[:public][:tables][name] = {
        primary_key: primary_key,
        columns:     columns,
      }
    end

    private

    attr_accessor :schemas
  end
end
