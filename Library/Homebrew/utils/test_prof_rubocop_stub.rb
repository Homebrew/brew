# typed: strict
# frozen_string_literal: true

require_relative "../warnings"

# TestProf's RuboCop plugin has two issues that we need to work around:
#
# 1. It references RuboCop::TestProf::Plugin::VERSION, which does not exist.
#    To solve this, we define the constant ourselves, which requires creating a dummy LintRoller::Plugin class.
#    This should be fixed in the next version of TestProf.
#    See: https://github.com/test-prof/test-prof/commit/a151a513373563ed8fa7f8e56193138d3ee9b5e3
#
# 2. It checks the RuboCop version using a method that is incompatible with our RuboCop setup.
#    To bypass this check, we need to manually require the necessary files. More details below.

module LintRoller
  # Dummy class to satisfy TestProf's reference to LintRoller::Plugin.
  class Plugin; end # rubocop:disable Lint/EmptyClass
end

module RuboCop
  module TestProf
    class Plugin < LintRoller::Plugin
      VERSION = "1.5.0"
    end
  end
end

# TestProf is not able to detect what version of RuboCop we're using, so we need to manually import its cops.
# For more details, see https://github.com/test-prof/test-prof/blob/v1.5.0/lib/test_prof/rubocop.rb
# TODO: This will change in the next version of TestProf.
#       See: https://github.com/test-prof/test-prof/commit/a151a513373563ed8fa7f8e56193138d3ee9b5e3
Warnings.ignore(/TestProf cops require RuboCop >= 0.51.0 to run/) do
  # All this file does is check the RuboCop version and require the files below.
  # If we don't require this now while the warning is ignored, we'll see the warning again later
  # when RuboCop requires the file.
  require "test_prof/rubocop"

  # This is copied from test-prof/rubocop.rb, and is necessary because that file returns early if the RuboCop version
  # check isn't met.
  require "test_prof/cops/plugin"
  require "test_prof/cops/rspec/aggregate_examples"
end
