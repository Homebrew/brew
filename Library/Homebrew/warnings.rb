# typed: strict
# frozen_string_literal: true

# Helper module for handling warnings.
module Warnings
  module Filter
    sig { params(message: String, category: T.nilable(Symbol)).void }
    def warn(message, category: nil)
      return if Warnings.ignored?(message)

      Kernel.raise message if Warnings.fatal?(message)

      super
    end
  end

  COMMON_WARNINGS = T.let({
    parser_syntax: [
      %r{warning: parser/current is loading parser/ruby\d+, which recognizes},
      /warning: \d+\.\d+\.\d+-compliant syntax, but you are running \d+\.\d+\.\d+\./,
      %r{warning: please see https://github\.com/whitequark/parser#compatibility-with-ruby-mri\.},
    ],
  }.freeze, T::Hash[Symbol, T::Array[Regexp]])
  private_constant :COMMON_WARNINGS

  IGNORED_WARNINGS_KEY = :homebrew_ignored_warnings
  private_constant :IGNORED_WARNINGS_KEY

  FATAL_WARNINGS_KEY = :homebrew_fatal_warnings
  private_constant :FATAL_WARNINGS_KEY

  @fatal_warnings = T.let([], T::Array[Regexp])

  sig { params(warnings: T.any(Symbol, Regexp), _block: T.proc.void).void }
  def self.ignore(*warnings, &_block)
    warnings = expand(warnings)

    previous_warnings = ignored_warnings
    Thread.current.thread_variable_set(IGNORED_WARNINGS_KEY, previous_warnings + warnings)
    begin
      yield
    ensure
      Thread.current.thread_variable_set(IGNORED_WARNINGS_KEY, previous_warnings)
    end
  end

  sig { params(warnings: T.any(Symbol, Regexp), block: T.nilable(T.proc.void)).void }
  def self.fail_on(*warnings, &block)
    warnings = expand(warnings)
    unless block
      @fatal_warnings = (@fatal_warnings + warnings).uniq
      return
    end

    previous_warnings = fatal_warnings
    Thread.current.thread_variable_set(FATAL_WARNINGS_KEY, previous_warnings + warnings)
    begin
      yield
    ensure
      Thread.current.thread_variable_set(FATAL_WARNINGS_KEY, previous_warnings)
    end
  end

  sig { params(message: String).returns(T::Boolean) }
  def self.ignored?(message)
    ignored_warnings.any? { |warning| warning.match?(message) }
  end

  sig { params(message: String).returns(T::Boolean) }
  def self.fatal?(message)
    @fatal_warnings.any? { |warning| warning.match?(message) } ||
      fatal_warnings.any? { |warning| warning.match?(message) }
  end

  sig { params(warnings: T::Array[T.any(Symbol, Regexp)]).returns(T::Array[Regexp]) }
  def self.expand(warnings)
    warnings.flat_map do |warning|
      warning.is_a?(Symbol) ? COMMON_WARNINGS.fetch(warning) : warning
    end
  end
  private_class_method :expand

  sig { returns(T::Array[Regexp]) }
  def self.ignored_warnings
    Thread.current.thread_variable_get(IGNORED_WARNINGS_KEY) || []
  end
  private_class_method :ignored_warnings

  sig { returns(T::Array[Regexp]) }
  def self.fatal_warnings
    Thread.current.thread_variable_get(FATAL_WARNINGS_KEY) || []
  end
  private_class_method :fatal_warnings

  Warning.singleton_class.prepend(Filter)
  private_constant :Filter
end
