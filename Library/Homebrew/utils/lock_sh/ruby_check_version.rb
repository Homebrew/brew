# typed: strict
# frozen_string_literal: true

ruby_version_to_check = ARGV.first
exit(ruby_version_to_check < RUBY_VERSION)
