# typed: strict
# frozen_string_literal: true

require "bundle/checker"

module Homebrew
  module Bundle
    module Checker
      class FlatpakRemoteChecker < Homebrew::Bundle::Checker::Base
        PACKAGE_TYPE = :flatpak_remote
        PACKAGE_TYPE_NAME = "Flatpak Remote"

        sig {
          params(entries: T::Array[Homebrew::Bundle::Dsl::Entry], exit_on_first_error: T::Boolean,
                 no_upgrade: T::Boolean, verbose: T::Boolean).returns(T::Array[String])
        }
        def find_actionable(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
          return [] if OS.mac?

          requested_remotes = format_checkable(entries)
          return [] if requested_remotes.empty?

          require "bundle/flatpak_remote_dumper"
          current_remotes = Homebrew::Bundle::FlatpakRemoteDumper.remote_names
          (requested_remotes - current_remotes).map { |entry| "Flatpak Remote #{entry} needs to be added." }
        end
      end
    end
  end
end
