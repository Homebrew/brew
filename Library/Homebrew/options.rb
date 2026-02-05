# typed: strict
# frozen_string_literal: true

# A formula option.
class Option
  sig { returns(String) }
  attr_reader :name

  sig { returns(String) }
  attr_reader :description, :flag

  sig { params(name: String, description: String).void }
  def initialize(name, description = "")
    @name = name
    @flag = T.let("--#{name}", String)
    @description = description
  end

  sig { returns(String) }
  def to_s = flag

  sig { params(other: T.anything).returns(T.nilable(Integer)) }
  def <=>(other)
    case other
    when Option
      name <=> other.name
    end
  end

  sig { params(other: T.anything).returns(T::Boolean) }
  def ==(other)
    case other
    when Option
      instance_of?(other.class) && name == other.name
    else
      false
    end
  end
  alias eql? ==

  sig { returns(Integer) }
  def hash
    name.hash
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{flag.inspect}>"
  end
end

# A deprecated formula option.
class DeprecatedOption
  sig { returns(String) }
  attr_reader :old, :current

  sig { params(old: String, current: String).void }
  def initialize(old, current)
    @old = old
    @current = current
  end

  sig { returns(String) }
  def old_flag
    "--#{old}"
  end

  sig { returns(String) }
  def current_flag
    "--#{current}"
  end

  sig { params(other: T.anything).returns(T::Boolean) }
  def ==(other)
    case other
    when DeprecatedOption
      instance_of?(other.class) && old == other.old && current == other.current
    else
      false
    end
  end
  alias eql? ==
end

# A collection of formula options.
class Options
  include Enumerable
  extend T::Generic

  Elem = type_member(:out) { { fixed: Option } }

  sig { params(array: T.nilable(T::Array[String])).returns(Options) }
  def self.create(array)
    new Array(array).map { |e| Option.new(e[/^--([^=]+=?)(.+)?$/, 1] || e) }
  end

  sig { params(options: T.nilable(T::Enumerable[Option])).void }
  def initialize(options = nil)
    # Ensure this is synced with `initialize_dup` and `freeze` (excluding simple objects like integers and booleans)
    @options = T.let(Set.new(options), T::Set[Option])
  end

  sig { params(other: Options).void }
  def initialize_dup(other)
    super
    @options = @options.dup
  end

  sig { returns(T.self_type) }
  def freeze
    @options.dup
    super
  end

  sig { override.params(block: T.proc.params(arg0: Option).returns(BasicObject)).returns(T.self_type) }
  def each(&block)
    @options.each(&block)
    self
  end

  sig { params(other: Option).returns(T.self_type) }
  def <<(other)
    @options << other
    self
  end

  sig { params(other: T::Enumerable[Option]).returns(T.self_type) }
  def +(other)
    self.class.new(@options + other)
  end

  sig { params(other: T::Enumerable[Option]).returns(T.self_type) }
  def -(other)
    self.class.new(@options - other)
  end

  sig { params(other: T::Enumerable[Option]).returns(T.self_type) }
  def &(other)
    self.class.new(@options & other)
  end

  sig { params(other: T::Enumerable[Option]).returns(T.self_type) }
  def |(other)
    self.class.new(@options | other)
  end

  sig { params(other: String).returns(String) }
  def *(other)
    @options.to_a * other
  end

  sig { params(other: T.anything).returns(T::Boolean) }
  def ==(other)
    case other
    when Options
      instance_of?(other.class) && to_a == other.to_a
    else
      false
    end
  end
  alias eql? ==

  sig { returns(T::Boolean) }
  def empty?
    @options.empty?
  end

  sig { returns(T::Array[String]) }
  def as_flags
    map(&:flag)
  end

  sig { params(option: T.any(Option, String)).returns(T::Boolean) }
  def include?(option)
    any? { |opt| opt == option || opt.name == option || opt.flag == option }
  end

  alias to_ary to_a

  sig { returns(String) }
  def to_s
    @options.map(&:to_s).join(" ")
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{to_a.inspect}>"
  end

  sig { params(formula: Formula).void }
  def self.dump_for_formula(formula)
    formula.options.sort_by(&:flag).each do |opt|
      puts "#{opt.flag}\n\t#{opt.description}"
    end
    puts "--HEAD\n\tInstall HEAD version" if formula.head
  end
end
