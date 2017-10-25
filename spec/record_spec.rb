require 'pgvc/record'
require 'pp'

RSpec.describe 'Record' do
  def record(hash)
    Pgvc::Record.new hash
  end

  it 'takes a postgresql result and makes the keys available as methods' do
    expect(record("a" => "b").a).to eq "b"
  end

  describe 'bracket access and fetch' do
    it 'allows hash style fetch access' do
      expect(record('a' => 'b').fetch('a')).to eq 'b'
      expect { record('a' => 'b').fetch('x') }.to raise_error KeyError
    end

    it 'allows hash style bracket access, but it behaves like fetch' do
      expect(record('a' => 'b')['a']).to eq 'b'
      expect { record('a' => 'b')['x'] }.to raise_error KeyError
    end

    it 'allows access by strings or symols (aka indifferent access)' do
      expect(record('a' => 'b')['a']).to eq 'b'
      expect(record('a' => 'b')[:a]).to eq 'b'
    end
  end

  it 'is equal to another record with the same keys and values' do
    expect(record('a' => 'b')).to eq record('a' => 'b')
    expect(record('a' => 'b')).to_not eq record('a' => 'c')
    expect(record('a' => 'b')).to_not eq record('c' => 'b')
    expect(record('a' => 'b')).to_not eq record('a' => 'b', 'c' => 'd')
  end

  describe 'booleans' do
    it 'treats \'t\' and \'f\' as true and false' do
      expect(record('is_a' => 't').is_a).to equal true
      expect(record('is_a' => 'f').is_a).to equal false
    end
    it 'treats \'1\' and \'0\' as true and false' do
      expect(record('is_a' => '1').is_a).to equal true
      expect(record('is_a' => '0').is_a).to equal false
    end
    it 'does this only when the key begins with is_' do
      expect(record('is_a' => 't').is_a).to eq true
      expect(record('is_'  => 't').is_).to eq 't'
      expect(record('isa'  => 't').isa).to eq 't'
      expect(record('a'    => 't').a).to eq 't'
    end
    it 'allows ruby style #predicate? as well as the underlying #is_predicate' do
      expect(record('is_a' => 't').a?).to equal true
      expect(record('is_a' => 't').is_a).to equal true
      expect { record('isa' => 't').a? }
        .to raise_error NoMethodError
    end
  end

  it 'inspects similarly to a struct' do
    expect(record('a' => 'b', 'is_a' => 't').inspect)
      .to eq '#<Record a="b" is_a=true>'
  end

  it 'pretty inspects similarly to a hash' do
    r = record(vc_hash:  "0d398289f4d7530385520236f434ad1a",
               db_hash:  "58bf94a8ca3f0c7761d3ca150e1b8622",
               user_ref: "Josh Cheek",
               summary:  "Add white shoes")
    expect(PP.pp(r, '')).to eq <<~RUBY
      #<Record vc_hash="0d398289f4d7530385520236f434ad1a"
               db_hash="58bf94a8ca3f0c7761d3ca150e1b8622"
               user_ref="Josh Cheek"
               summary="Add white shoes">
    RUBY
  end
end
