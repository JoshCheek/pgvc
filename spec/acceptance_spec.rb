# Using a hypothetical blog (users/posts) to figure out what its behaviour should be and drive its implementation

RSpec.describe 'Figuring out what it should do' do
  describe 'initial state' do
    it 'starts on the root branch pointing at the root commit, which is empty'
  end

  describe 'branches' do
    it 'can create and delete branches'
    it 'can create a branch pointing to an arbitrary commit'
    it 'remembers which branch it is on'
    it 'returns to the root branch when it deletes the branch it is on'
  end

  describe 'when making changes' do
    # I suppose, ideally, it would record the current user/time when doing this,
    # but I think that would require changes to existing queries
    it 'creates a new incomplete commit to hold the changes and points the branch at it'
    it 'sets the old commit as a parent of the new commit'
    it 'can insert rows and query them back out'
    it 'can update rows and query them backout'
    it 'can insert and delete rows, which do not come back out when queried'
    it 'groups all the changes together on the incomplete commit'
  end


  describe 'committing' do
    it 'accepts a synopsis, description, user, and time'

    describe 'when the commit is incomplete' do
      it 'completes the commit'
      it 'does not update the branch'
    end

    describe 'when the commit is complete' do
      it 'creates a new complete commit, which is empty'
      it 'makes the old commit a parent of the new commit'
    end
  end

  describe 'history' do
    it 'knows the parents of a given commit'
    it 'displays the database as it looks from a given branch'
  end

  describe 'diffing returns the set of changes between two commits' do
    example 'an empty commit'
    example 'insertions'
    example 'deletions'
    example 'updates'
    example 'inserting and then deleting has no diff'
    example 'inserting and updating is just inserting'
    example 'updating and updating is just updating (for whichever came last)'
    example 'updating and deleting is just a deletinv'
  end
end
