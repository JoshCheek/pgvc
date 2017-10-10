class Result
  def initialize(result_hash)
    @hash = result_hash.map { |k, v| [k.intern, v] }.to_h
  end

  def respond_to_missing(name)
    @hash.key? name
  end

  def method_missing(name)
    return @hash.fetch name if @hash.key? name
    super
  end

  def inspect
    PP.pp(self, '')
  end

  def pretty_print(pp)
    pp.group 2, "#<Result", '>' do
      @hash.each.with_index do |(k, v), i|
        pp.breakable ' '
        pp.text "#{k}=#{v.inspect}"
      end
    end
  end
end
