# typed: strict
# frozen_string_literal: true

# TestProf attempts to check for a supported RuboCop version using a method that is incompatible with our setup.
# We load the TestProf plugin manually (as opposed to letting RuboCop automatically load it) to prevent the version check from running.
# The `require` calls are copied from https://github.com/test-prof/test-prof/blob/v1.5.1/lib/rubocop/test_prof.rb
require "rubocop/test_prof/plugin"
require "rubocop/test_prof/cops/rspec/aggregate_examples"
