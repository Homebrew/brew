# frozen_string_literal: true
##
# Provides 3 methods for declaring when something is going away.
#
# +deprecate(name, repl, year, month)+:
#     Indicate something may be removed on/after a certain date.
#
# +rubygems_deprecate(name, replacement=:none)+:
#     Indicate something will be removed in the next major RubyGems version,
#     and (optionally) a replacement for it.
#
# +rubygems_deprecate_command+:
#     Indicate a RubyGems command (in +lib/rubygems/commands/*.rb+) will be
#     removed in the next RubyGems version.
#
# Also provides +skip_during+ for temporarily turning off deprecation warnings.
# This is intended to be used in the test suite, so deprecation warnings
# don't cause test failures if you need to make sure stderr is otherwise empty.
#
#
# Example usage of +deprecate+ and +rubygems_deprecate+:
#
#     class Legacy
#       def self.some_class_method
#         # ...
#       end
#
#       def some_instance_method
#         # ...
#       end
#
#       def some_old_method
#         # ...
#       end
#
#       extend Gem::Deprecate
#       deprecate :some_instance_method, "X.z", 2011, 4
#       rubygems_deprecate :some_old_method, "Modern#some_new_method"
#
#       class << self
#         extend Gem::Deprecate
#         deprecate :some_class_method, :none, 2011, 4
#       end
#     end
#
#
# Example usage of +rubygems_deprecate_command+:
#
#     class Gem::Commands::QueryCommand < Gem::Command
#       extend Gem::Deprecate
#       rubygems_deprecate_command
#
#       # ...
#     end
#
#
# Example usage of +skip_during+:
#
#     class TestSomething < Gem::Testcase
#       def test_some_thing_with_deprecations
#         Gem::Deprecate.skip_during do
#           actual_stdout, actual_stderr = capture_output do
#             Gem.something_deprecated
#           end
#           assert_empty actual_stdout
#           assert_equal(expected, actual_stderr)
#         end
#       end
#     end

module Gem::Deprecate

  def self.skip # :nodoc:
    @skip ||= false
  end

  def self.skip=(v) # :nodoc:
    @skip = v
  end

  ##
  # Temporarily turn off warnings. Intended for tests only.

  def skip_during
    Gem::Deprecate.skip, original = true, Gem::Deprecate.skip
    yield
  ensure
    Gem::Deprecate.skip = original
  end

  def self.next_rubygems_major_version # :nodoc:
    Gem::Version.new(Gem.rubygems_version.segments.first).bump
  end

  ##
  # Simple deprecation method that deprecates +name+ by wrapping it up
  # in a dummy method. It warns on each call to the dummy method
  # telling the user of +repl+ (unless +repl+ is :none) and the
  # year/month that it is planned to go away.

  def deprecate(name, repl, year, month)
    class_eval do
      old = "_deprecated_#{name}"
      alias_method old, name
      define_method name do |*args, &block|
        klass = self.kind_of? Module
        target = klass ? "#{self}." : "#{self.class}#"
        msg = [ "NOTE: #{target}#{name} is deprecated",
                repl == :none ? " with no replacement" : "; use #{repl} instead",
                ". It will be removed on or after %4d-%02d." % [year, month],
                "\n#{target}#{name} called from #{Gem.location_of_caller.join(":")}",
        ]
        warn "#{msg.join}." unless Gem::Deprecate.skip
        send old, *args, &block
      end
      ruby2_keywords name if respond_to?(:ruby2_keywords, true)
    end
  end

  ##
  # Simple deprecation method that deprecates +name+ by wrapping it up
  # in a dummy method. It warns on each call to the dummy method
  # telling the user of +repl+ (unless +repl+ is :none) and the
  # Rubygems version that it is planned to go away.

  def rubygems_deprecate(name, replacement=:none)
    class_eval do
      old = "_deprecated_#{name}"
      alias_method old, name
      define_method name do |*args, &block|
        klass = self.kind_of? Module
        target = klass ? "#{self}." : "#{self.class}#"
        msg = [ "NOTE: #{target}#{name} is deprecated",
                replacement == :none ? " with no replacement" : "; use #{replacement} instead",
                ". It will be removed in Rubygems #{Gem::Deprecate.next_rubygems_major_version}",
                "\n#{target}#{name} called from #{Gem.location_of_caller.join(":")}",
        ]
        warn "#{msg.join}." unless Gem::Deprecate.skip
        send old, *args, &block
      end
      ruby2_keywords name if respond_to?(:ruby2_keywords, true)
    end
  end

  # Deprecation method to deprecate Rubygems commands
  def rubygems_deprecate_command
    class_eval do
      define_method "deprecated?" do
        true
      end

      define_method "deprecation_warning" do
        msg = [ "#{self.command} command is deprecated",
                ". It will be removed in Rubygems #{Gem::Deprecate.next_rubygems_major_version}.\n",
        ]

        alert_warning "#{msg.join}" unless Gem::Deprecate.skip
      end
    end
  end

  module_function :rubygems_deprecate, :rubygems_deprecate_command, :skip_during

end
