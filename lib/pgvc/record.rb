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
      if @hash.key? name
        @hash.fetch name
      elsif name =~ /^(.*)\?$/ && @hash.key?(:"is_#$1")
        case result = @hash.fetch(:"is_#$1")
        when 'f', '0', 0, false then false
        when 't', '1', 1, true  then true
        else result
        end
      else
        super
      end
    end

    def [](key)
      @hash[key.intern]
    end

    def inspect
      "#<Record#{@hash.map { |k, v| " #{k}=#{v.inspect}" }.join}>"
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
