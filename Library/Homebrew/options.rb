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
require "options/deprecated_option"
require "options/options"
