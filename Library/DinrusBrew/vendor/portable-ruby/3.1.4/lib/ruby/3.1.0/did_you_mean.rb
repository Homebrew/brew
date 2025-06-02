require_relative "did_you_mean/version"
require_relative "did_you_mean/core_ext/name_error"

require_relative "did_you_mean/spell_checker"
require_relative 'did_you_mean/spell_checkers/name_error_checkers'
require_relative 'did_you_mean/spell_checkers/method_name_checker'
require_relative 'did_you_mean/spell_checkers/key_error_checker'
require_relative 'did_you_mean/spell_checkers/null_checker'
require_relative 'did_you_mean/spell_checkers/require_path_checker'
require_relative 'did_you_mean/spell_checkers/pattern_key_name_checker'
require_relative 'did_you_mean/formatter'
require_relative 'did_you_mean/tree_spell_checker'

# The +DidYouMean+ gem adds functionality to suggest possible method/class
# names upon errors such as +NameError+ and +NoMethodError+. In Ruby 2.3 or
# later, it is automatically activated during startup.
#
# @example
#
#   methosd
#   # => NameError: undefined local variable or method `methosd' for main:Object
#   #   Did you mean?  methods
#   #                  method
#
#   OBject
#   # => NameError: uninitialized constant OBject
#   #    Did you mean?  Object
#
#   @full_name = "Yuki Nishijima"
#   first_name, last_name = full_name.split(" ")
#   # => NameError: undefined local variable or method `full_name' for main:Object
#   #    Did you mean?  @full_name
#
#   @@full_name = "Yuki Nishijima"
#   @@full_anme
#   # => NameError: uninitialized class variable @@full_anme in Object
#   #    Did you mean?  @@full_name
#
#   full_name = "Yuki Nishijima"
#   full_name.starts_with?("Y")
#   # => NoMethodError: undefined method `starts_with?' for "Yuki Nishijima":String
#   #    Did you mean?  start_with?
#
#   hash = {foo: 1, bar: 2, baz: 3}
#   hash.fetch(:fooo)
#   # => KeyError: key not found: :fooo
#   #    Did you mean?  :foo
#
#
# == Disabling +did_you_mean+
#
# Occasionally, you may want to disable the +did_you_mean+ gem for e.g.
# debugging issues in the error object itself. You can disable it entirely by
# specifying +--disable-did_you_mean+ option to the +ruby+ command:
#
#   $ ruby --disable-did_you_mean -e "1.zeor?"
#   -e:1:in `<main>': undefined method `zeor?' for 1:Integer (NameError)
#
# When you do not have direct access to the +ruby+ command (e.g.
# +rails console+, +irb+), you could applyoptions using the +RUBYOPT+
# environment variable:
#
#   $ RUBYOPT='--disable-did_you_mean' irb
#   irb:0> 1.zeor?
#   # => NoMethodError (undefined method `zeor?' for 1:Integer)
#
#
# == Getting the original error message
#
# Sometimes, you do not want to disable the gem entirely, but need to get the
# original error message without suggestions (e.g. testing). In this case, you
# could use the +#original_message+ method on the error object:
#
#   no_method_error = begin
#                       1.zeor?
#                     rescue NoMethodError => error
#                       error
#                     end
#
#   no_method_error.message
#   # => NoMethodError (undefined method `zeor?' for 1:Integer)
#   #    Did you mean?  zero?
#
#   no_method_error.original_message
#   # => NoMethodError (undefined method `zeor?' for 1:Integer)
#
module DidYouMean
  # Map of error types and spell checker objects.
  @spell_checkers = Hash.new(NullChecker)

  # Returns a sharable hash map of error types and spell checker objects.
  def self.spell_checkers
    @spell_checkers
  end

  # Adds +DidYouMean+ functionality to an error using a given spell checker
  def self.correct_error(error_class, spell_checker)
    if defined?(Ractor)
      new_mapping = { **@spell_checkers, error_class.to_s => spell_checker }
      new_mapping.default = NullChecker

      @spell_checkers = Ractor.make_shareable(new_mapping)
    else
      spell_checkers[error_class.to_s] = spell_checker
    end

    error_class.prepend(Correctable) if error_class.is_a?(Class) && !(error_class < Correctable)
  end

  correct_error NameError, NameErrorCheckers
  correct_error KeyError, KeyErrorChecker
  correct_error NoMethodError, MethodNameChecker
  correct_error LoadError, RequirePathChecker if RUBY_VERSION >= '2.8.0'
  correct_error NoMatchingPatternKeyError, PatternKeyNameChecker if defined?(::NoMatchingPatternKeyError)

  # TODO: Remove on 3.3:
  class DeprecatedMapping # :nodoc:
    def []=(key, value)
      warn "Calling `DidYouMean::SPELL_CHECKERS[#{key.to_s}] = #{value.to_s}' has been deprecated. " \
           "Please call `DidYouMean.correct_error(#{key.to_s}, #{value.to_s})' instead."

      DidYouMean.correct_error(key, value)
    end

    def merge!(hash)
      warn "Calling `DidYouMean::SPELL_CHECKERS.merge!(error_name => spell_checker)' has been deprecated. " \
           "Please call `DidYouMean.correct_error(error_name, spell_checker)' instead."

      hash.each do |error_class, spell_checker|
        DidYouMean.correct_error(error_class, spell_checker)
      end
    end
  end

  # TODO: Remove on 3.3:
  SPELL_CHECKERS = DeprecatedMapping.new
  deprecate_constant :SPELL_CHECKERS
  private_constant :DeprecatedMapping

  # Returns the currently set formatter. By default, it is set to +DidYouMean::Formatter+.
  def self.formatter
    if defined?(Ractor)
      Ractor.current[:__did_you_mean_formatter__] || Formatter
    else
      Formatter
    end
  end

  # Updates the primary formatter used to format the suggestions.
  def self.formatter=(formatter)
    if defined?(Ractor)
      Ractor.current[:__did_you_mean_formatter__] = formatter
    end
  end
end
