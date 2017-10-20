class Pgvc
  BaseError = Class.new StandardError
  InvalidColumn = Class.new BaseError

  DEFAULT_BRANCH_NAME = 'primary'.freeze

  def initialize
    root_commit = Commit.new id: next_id!, parents: [], complete: true
    branch = Branch.new name: DEFAULT_BRANCH_NAME, commit: root_commit
    self.all_branches = {branch.name => branch}
    self.current_branch_name = branch.name
    self.tables = {}
  end

  def switch_branch(new_branch_name)
    self.current_branch_name = new_branch_name
    self
  end

  def commit
    branch.commit
  end

  def branch
    all_branches.fetch current_branch_name
  end

  def branches
    all_branches.values
  end

  def create_branch(name)
    fixme = Commit.new id: next_id!, parents: [], complete: true
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
      switch_branch DEFAULT_BRANCH_NAME
    self
  end

  def select_all(table_name)
    table table_name
  end

  def insert(table_name, attributes)
    branch.open_commit! next_id! if commit.complete?
    table(table_name) << attributes
    self
  end

  def update(table_name, where:, to:)
    table(table_name)
      .select { |row| match? row, where }
      .each   { |row| row.merge! to }
    self
  end

  def delete(table_name, where:)
    table(table_name).reject! { |row| match? row, where }
    self
  end

  def commit!(attributes)
    branch.open_commit! next_id!  if commit.complete?
    commit.complete! attributes
    self
  end

  private

  attr_accessor :all_branches, :current_branch_name, :tables

  def next_id!
    @current_id ||= 0
    @current_id = @current_id + 1
  end

  def table(name)
    return tables.fetch name if tables.include? name
    tables[name] = []
  end

  def match?(row, criteria)
    criteria.all? do |key, value|
      row[key] == value
    end
  end
end


class Pgvc
  class Branch
    CannotCreate = Class.new BaseError
    CannotDelete = Class.new BaseError

    attr_reader :name, :commit
    def initialize(name:, commit:)
      self.name = name
      self.commit = commit
    end

    def open_commit!(id)
      raise "WTF?" unless commit.complete?
      self.commit = Commit.new id: id, parents: [commit], complete: false
      self
    end

    private

    attr_writer :name, :commit
  end
end


class Pgvc
  class Commit
    attr_reader :id, :parents, :synopsis, :description, :user, :time

    def initialize(id:, parents:, complete:)
      self.id       = id
      self.parents  = parents
      self.complete = complete
    end

    def complete?
      complete
    end

    def complete!(synopsis:, description:, user:, time:)
      raise "Wtf?" if complete?
      self.complete    = true
      self.synopsis    = synopsis
      self.description = description
      self.user        = user
      self.time        = time
    end

    def [](key)
      case key
      when :id                   then id
      when :synopsis             then synopsis
      when :description          then description
      when :user                 then user
      when :time                 then time
      when :complete, :complete? then complete?
      else raise "Not an attribute: #{key.inspect}"
      end
    end

    private

    attr_accessor :complete
    attr_writer :id, :parents, :synopsis, :description, :user, :time
  end
end
