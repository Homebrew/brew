# typed: true
# frozen_string_literal: true

require "cli/parser"
require "utils/spdx"
require "system_command"

module Homebrew
  include SystemCommand::Mixin

  module_function

  sig { returns(CLI::Parser) }
  def update_license_data_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Update SPDX license data in the Homebrew repository.
      EOS
      named_args :none
    end
  end

  def update_license_data
    update_license_data_args.parse

    SPDX.download_latest_license_data!
    diff = system_command "git", args: [
      "-C", HOMEBREW_REPOSITORY, "diff", "--exit-code", SPDX::DATA_PATH
    ]
    if diff.status.success?
      ofail "No changes to SPDX license data."
    else
      puts "SPDX license data updated."
    end
  end
end
