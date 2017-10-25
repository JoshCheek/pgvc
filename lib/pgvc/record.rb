class Pgvc
  class Record
    def initialize(result_hash)
      @hash = result_hash.map do |k, v|
        [k.intern, normalize_value(k, v)]
      end.to_h
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
        @hash.fetch :"is_#$1"
      else
        super
      end
    end

    def fetch(key)
      @hash.fetch key.intern
    end

    alias [] fetch

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

    private

    def normalize_value(key, value)
      return value unless key =~ /^is_(.+)$/
      case value
      when 'f', '0' then false
      when 't', '1' then true
      else value
      end
    end
  end
end
