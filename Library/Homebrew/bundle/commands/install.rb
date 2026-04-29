# typed: strict
# frozen_string_literal: true

require "utils"
require "utils/output"
require "bundle/brewfile"
require "bundle/installer"
require "bundle/locker"

module Homebrew
  module Bundle
    module Commands
      module Install
        extend Utils::Output::Mixin

        sig {
          params(
            global:     T::Boolean,
            file:       T.nilable(String),
            no_lock:    T::Boolean,
            no_upgrade: T::Boolean,
            verbose:    T::Boolean,
            force:      T::Boolean,
            jobs:       Integer,
            quiet:      T::Boolean,
            lock:       T::Boolean,
          ).void
        }
        def self.run(global: false, file: nil, no_lock: false, no_upgrade: false, verbose: false,
                     force: false, jobs: 1, quiet: false, lock: false)
          @dsl = Brewfile.read(global:, file:)
          # no_lock retained for legacy callers; --lock is the active opt-in for Phase 1.
          result = Homebrew::Bundle::Installer.install!(
            @dsl.entries,
            global:, file:, no_lock:, no_upgrade:, verbose:, force:, jobs:, quiet:,
          )

          if result && lock
            brewfile_path = Brewfile.path(global:, file:)
            begin
              lockfile = Homebrew::Bundle::Locker.lock(entries: @dsl.entries, file: brewfile_path)
              puts "Wrote #{lockfile}"
            rescue => e
              opoo "Failed to write Brewfile.lock.json: #{e.message}"
            end
          end

          # Mark Brewfile formulae as installed_on_request to prevent autoremove
          # from removing them when their dependents are uninstalled
          Homebrew::Bundle.mark_as_installed_on_request!(@dsl.entries)

          result || exit(1)
        end

        sig { returns(T.nilable(Dsl)) }
        def self.dsl
          @dsl ||= T.let(nil, T.nilable(Dsl))
          @dsl
        end
      end
    end
  end
end
