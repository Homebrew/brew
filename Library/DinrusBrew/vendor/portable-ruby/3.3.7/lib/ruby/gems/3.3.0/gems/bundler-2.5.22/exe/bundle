#!/usr/bin/env ruby
# frozen_string_literal: true

# Exit cleanly from an early interrupt
Signal.trap("INT") do
  Bundler.ui.debug("\n#{caller.join("\n")}") if defined?(Bundler)
  exit 1
end

base_path = File.expand_path("../lib", __dir__)

if File.exist?(base_path)
  $LOAD_PATH.unshift(base_path)
end

require "bundler"

require "bundler/friendly_errors"

Bundler.with_friendly_errors do
  require "bundler/cli"

  # Allow any command to use --help flag to show help for that command
  help_flags = %w[--help -h]
  help_flag_used = ARGV.any? {|a| help_flags.include? a }
  args = help_flag_used ? Bundler::CLI.reformatted_help_args(ARGV) : ARGV

  Bundler::CLI.start(args, debug: true)
end
