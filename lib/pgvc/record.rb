require 'pp'

class Pgvc
  class Record
    def initialize(result_hash)
      @hash = result_hash.map { |k, v| [k.intern, v] }.to_h
    end
    def to_h
      @hash.dup
    end
    def ==(other)
      to_h == other.to_h
    end
    def respond_to_missing(name)
      @hash.key? name
    end
    def method_missing(name, *)
      return @hash.fetch name if @hash.key? name
      super
    end
    def [](key)
      @hash[key.intern]
    end
    def inspect
      ::PP.pp(self, '').chomp
    end
    def pretty_print(pp)
      pp.text "#<Record "
      pp.group 9 do
        @hash.each.with_index do |(k, v), i|
          pp.text "#{k}=#{v.inspect}"
          pp.breakable ' ' unless i == @hash.length-1
        end
      end
      pp.text '>'
    end
  end
end
