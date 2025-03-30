# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "bundle/mac_app_store_installer"

module Homebrew
  module Bundle
    module Checker
      class MacAppStoreChecker < Homebrew::Bundle::Checker::Base
        PACKAGE_TYPE = :mas
        PACKAGE_TYPE_NAME = "App"

        def installed_and_up_to_date?(id, no_upgrade: false)
          Homebrew::Bundle::MacAppStoreInstaller.app_id_installed_and_up_to_date?(id, no_upgrade:)
        end

        def format_checkable(entries)
          checkable_entries(entries).to_h { |e| [e.options[:id], e.name] }
        end

        def exit_early_check(app_ids_with_names, no_upgrade:)
          work_to_be_done = app_ids_with_names.find do |id, _name|
            !installed_and_up_to_date?(id, no_upgrade:)
          end

          Array(work_to_be_done)
        end

        def full_check(app_ids_with_names, no_upgrade:)
          app_ids_with_names.reject { |id, _name| installed_and_up_to_date?(id, no_upgrade:) }
                            .map { |_id, name| failure_reason(name, no_upgrade:) }
        end
      end
    end
  end
end
