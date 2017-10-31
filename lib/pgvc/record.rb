class Pgvc
  class Record
    def initialize(result_hash)
      self.attributes = result_hash.each_with_object({}) do |(k, v), h|
        h[k.intern] = normalize_value(k, v)
      end.to_h
    end

    def to_h
      attributes.dup
    end

    def to_a
      attributes.values
    end

    def ==(other)
      to_h == other.to_h
    end

    def respond_to_missing(name)
      attributes.key? name
    end

    def method_missing(name, *)
      if attributes.key? name
        attributes.fetch name
      elsif name =~ /^(.*)\?$/ && attributes.key?(:"is_#$1")
        attributes.fetch :"is_#$1"
      else
        super
      end
    end

    def fetch(key)
      attributes.fetch key.intern
    end

    alias [] fetch

    def inspect
      "#<Record#{attributes.map { |k, v| " #{k}=#{v.inspect}" }.join}>"
    end

    def pretty_print(pp)
      pp.text "#<Record "
      pp.group 9 do
        attributes.each.with_index do |(k, v), i|
          pp.text "#{k}=#{v.inspect}"
          pp.breakable ' ' unless i == attributes.length-1
        end
      end
      pp.text '>'
    end

    private

    attr_accessor :attributes

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
