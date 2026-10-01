# typed: strict
# frozen_string_literal: true

require "delegate"
require "dependency"
require "requirement"

# A collection of dependencies.
class Dependencies < SimpleDelegator
  extend T::Generic

  Elem = type_member(:out) { { fixed: Dependency } }

  sig { params(args: Dependency).void }
  def initialize(*args)
    super(args)
  end

  alias eql? ==

  sig { returns(T::Array[Dependency]) }
  def optional
    __getobj__.select(&:optional?)
  end

  sig { returns(T::Array[Dependency]) }
  def recommended
    __getobj__.select(&:recommended?)
  end

  sig { returns(T::Array[Dependency]) }
  def build
    __getobj__.select(&:build?)
  end

  sig { returns(T::Array[Dependency]) }
  def required
    __getobj__.select(&:required?)
  end

  sig { returns(T::Array[Dependency]) }
  def default
    build + required + recommended
  end

  sig { returns(Dependencies) }
  def dup_without_system_deps
    self.class.new(*__getobj__.reject { |dep| dep.uses_from_macos? && dep.use_macos_install? })
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{__getobj__}>"
  end
end
require "dependencies/requirements"
