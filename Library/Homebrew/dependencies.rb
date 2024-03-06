# typed: true
# frozen_string_literal: true

require "delegate"

# A collection of dependencies.
class Dependencies < SimpleDelegator
  def initialize(*args)
    super(args)
  end

  alias eql? ==

  def optional
    __getobj__.select(&:optional?)
  end

  def recommended
    __getobj__.select(&:recommended?)
  end

  def build
    __getobj__.select(&:build?)
  end

  def required
    __getobj__.select(&:required?)
  end

  def default
    build + required + recommended
  end

  def dup_without_system_deps
    self.class.new(*__getobj__.reject { |dep| dep.uses_from_macos? && dep.use_macos_install? })
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{__getobj__}>"
  end
end

# A collection of requirements.
class Requirements < SimpleDelegator
  def initialize(*args)
    super(Set.new(args))
  end

  def <<(other)
    if other.is_a?(Object) && other.is_a?(Comparable)
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
