# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "utils/spdx"
require "system_command"

module DinrusBrew
  module DevCmd
    class UpdateLicenseData < AbstractCommand
      include SystemCommand::Mixin

      cmd_args do
        description <<~EOS
          Update SPDX license data in the DinrusBrew repository.
        EOS
        named_args :none
      end

      sig { override.void }
      def run
        SPDX.download_latest_license_data!
        diff = system_command "git", args: [
          "-C", DINRUSBREW_REPOSITORY, "diff", "--exit-code", SPDX::DATA_PATH
        ]
        if diff.status.success?
          ofail "No changes to SPDX license data."
        else
          puts "SPDX license data updated."
        end
      end
    end
  end
end
