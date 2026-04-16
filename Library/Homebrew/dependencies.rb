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

# A collection of requirements.
class Requirements < SimpleDelegator # rubocop:todo Style/OneClassPerFile
  extend T::Generic

  Elem = type_member(:out) { { fixed: Requirement } }

  sig { params(args: Requirement).void }
  def initialize(*args)
    super(Set.new(args))
  end

  sig { params(other: Requirement).returns(Requirements) }
  def <<(other)
    if other.is_a?(Comparable)
      __getobj__.grep(other.class) do |req|
        return self if req > other

        __getobj__.delete(req)
      end
    end
    # see https://sorbet.org/docs/faq#how-can-i-fix-type-errors-that-arise-from-super
    T.bind(self, T.untyped)
    super
    self
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: {#{__getobj__.to_a.join(", ")}}>"
  end
end
