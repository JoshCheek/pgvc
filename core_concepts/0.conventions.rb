# The conventions we'll use in the following examples
require_relative 'helpers'

# =====  Annotations  =====
  # Display values with `# =>`, which comes from github.com/JoshCheek/seeing_is_believing
    123 # => 123

  # When the annotation is placed on the next line, it pretty-inspects the value
    [*'a'..'d'].map { |str| str * 20 }
    # => ['aaaaaaaaaaaaaaaaaaaa',
    #     'bbbbbbbbbbbbbbbbbbbb',
    #     'cccccccccccccccccccc',
    #     'dddddddddddddddddddd']

# =====  String inspection  =====
  # To make it easier to read, we'll inspect strings with double quotes instead
  # of single quotes, when there are a lot of double quotes in it
  {"a" => "b"}.inspect # => "{'a'=>'b'}"
  {a: :b}.inspect      # => '{:a=>:b}'

# =====  Running SQL  =====
  # This is a Ruby "here document", it creates a string
    <<~SQL
      select 1 as number
    SQL
    # => 'select 1 as number
    #    '

  # To run a SQL command:
    sql 'select 1 as number' # => [#<Record number='1'>]

  # Lets put them together
    sql <<~SQL
      select 1 as number
      union
      select 2 as number
    SQL
    # => [#<Record number='1'>, #<Record number='2'>]

# =====  Assertions  =====
  # `eq!` is an alias for `assert_equal`, it returns the value or raises
  eq! 2, 1+1           # => 2
  eq! 3, 1+1 rescue $! # => #<RuntimeError: Expected 3\nTo Equal 2>

  # `ne!` is an alias for `refute_equal`, it returns the RHS value
  ne! 3, 1+1           # => 2
  ne! 2, 1+1 rescue $! # => #<RuntimeError: Expected      2\nTo *NOT* Equal 2>

  # `assert!` returns the value, if it's not nil/false
  assert! ['a', 'b'][1]           # => 'b'
  assert! ['a', 'b'][2] rescue $! # => #<RuntimeError: failed assertion>
