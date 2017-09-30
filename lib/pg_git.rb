class PgGit
  BaseError = Class.new StandardError
  DEFAULT_BRANCH_NAME = 'primary'.freeze

  def initialize
    root_commit = Commit.new parents: []
    branch = Branch.new name: DEFAULT_BRANCH_NAME, commit: root_commit
    self.all_branches = {branch.name => branch}
    self.current_branch_name = branch.name
    self.tables = {}
  end

  def switch_branches(new_branch_name)
    self.current_branch_name = new_branch_name
    self
  end

  def branch
    all_branches.fetch current_branch_name
  end

  def branches
    all_branches.values
  end

  def create_branch(name)
    fixme = Commit.new parents: []
    all_branches.include? name and
      raise Branch::CannotCreate, "There is already a branch named #{name.inspect}"
    all_branches[name] = Branch.new name: name, commit: fixme
    self
  end

  def delete_branch(name)
    name == DEFAULT_BRANCH_NAME and
      raise Branch::CannotDelete, "Cannot delete the default branch, #{DEFAULT_BRANCH_NAME.inspect}"
    deleted = all_branches.delete(name)
    deleted.name == current_branch_name and
      switch_branches DEFAULT_BRANCH_NAME
    self
  end

  def select_all(table_name)
    table table_name
  end

  def insert(table_name, attributes)
    table(table_name) << attributes
    self
  end

  private

  attr_accessor :all_branches, :current_branch_name, :tables

  def table(name)
    return tables.fetch name if tables.include? name
    tables[name] = []
  end
end


class PgGit
  class Branch
    CannotCreate = Class.new BaseError
    CannotDelete = Class.new BaseError

    attr_reader :name, :commit
    def initialize(name:, commit:)
      self.name = name
      self.commit = commit
    end

    private

    attr_writer :name, :commit
  end
end


class PgGit
  class Commit
    attr_reader :parents
    def initialize(parents:)
      self.parents = parents
    end

    private

    attr_writer :parents
  end
end
