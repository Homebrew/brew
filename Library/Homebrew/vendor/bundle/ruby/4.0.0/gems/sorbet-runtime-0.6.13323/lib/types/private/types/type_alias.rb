# frozen_string_literal: true
# typed: true

module T::Private::Types
  # Wraps a proc for a type alias to defer its evaluation.
  class TypeAlias < T::Types::Base

    def initialize(callable)
      @callable = callable
      @checked_level = nil
    end

    def checked(level)
      if !@checked_level.nil?
        raise "You can't call .checked multiple times on a type alias."
      end
      if !T::Private::RuntimeLevels::LEVELS.include?(level)
        raise ArgumentError.new("Invalid `checked` level '#{level}'. Use one of: #{T::Private::RuntimeLevels::LEVELS}.")
      end
      @checked_level = level
      self
    end

    def build_type
      nil
    end

    def aliased_type
      @aliased_type ||= T::Utils.coerce(@callable.call)
    end

    def effective_aliased_type
      @effective_aliased_type ||= begin
        real_type = aliased_type
        level = @checked_level.nil? ? T::Private::RuntimeLevels.default_checked_level : @checked_level
        if level == :always || (level == :tests && T::Private::RuntimeLevels.check_tests?)
          real_type
        else
          T::Types::Anything::Private::INSTANCE
        end
      end
    end

    # overrides Base
    def name
      aliased_type.name
    end

    # overrides Base
    def recursively_valid?(obj)
      effective_aliased_type.recursively_valid?(obj)
    end

    # overrides Base
    def valid?(obj)
      effective_aliased_type.valid?(obj)
    end
  end
end
