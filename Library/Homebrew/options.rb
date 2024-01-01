# typed: true
# frozen_string_literal: true

# A formula option.
#
# @api private
class Option
  attr_reader :name, :description, :flag

  def initialize(name, description = "")
    @name = name
    @flag = "--#{name}"
    @description = description
  end

  def to_s
    flag
  end

  def <=>(other)
    return unless other.is_a?(Option)

    name <=> other.name
  end

  def ==(other)
    instance_of?(other.class) && name == other.name
  end
  alias eql? ==

  def hash
    name.hash
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{flag.inspect}>"
  end
end

# A deprecated formula option.
#
# @api private
class DeprecatedOption
  attr_reader :old, :current

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

  def ==(other)
    instance_of?(other.class) && old == other.old && current == other.current
  end
  alias eql? ==
end

# A collection of formula options.
#
# @api private
class Options
  include Enumerable

  def self.create(array)
    new Array(array).map { |e| Option.new(e[/^--([^=]+=?)(.+)?$/, 1] || e) }
  end

  def initialize(*args)
    # Ensure this is synced with `initialize_dup` and `freeze` (excluding simple objects like integers and booleans)
    @options = Set.new(*args)
  end

  def initialize_dup(other)
    super
    @options = @options.dup
  end

  def freeze
    @options.dup
    super
  end

  def each(*args, &block)
    @options.each(*args, &block)
  end

  def <<(other)
    @options << other
    self
  end

  def +(other)
    self.class.new(@options + other)
  end

  def -(other)
    self.class.new(@options - other)
  end

  def &(other)
    self.class.new(@options & other)
  end

  def |(other)
    self.class.new(@options | other)
  end

  def *(other)
    @options.to_a * other
  end

  def ==(other)
    instance_of?(other.class) &&
      to_a == other.to_a
  end
  alias eql? ==

  def empty?
    @options.empty?
  end

  def as_flags
    map(&:flag)
  end

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

  def self.dump_for_formula(formula)
    formula.options.sort_by(&:flag).each do |opt|
      puts "#{opt.flag}\n\t#{opt.description}"
    end
    puts "--HEAD\n\tInstall HEAD version" if formula.head
  end
end
