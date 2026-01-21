# typed: strict
# frozen_string_literal: true

require "bundle/brewfile"
require "bundle/installer"

module Homebrew
  module Bundle
    module Commands
      module Install
        sig {
          params(
            global:     T::Boolean,
            file:       T.nilable(String),
            no_lock:    T::Boolean,
            no_upgrade: T::Boolean,
            verbose:    T::Boolean,
            force:      T::Boolean,
            quiet:      T::Boolean,
          ).void
        }
        def self.run(global: false, file: nil, no_lock: false, no_upgrade: false, verbose: false, force: false,
                     quiet: false)
          @dsl = Brewfile.read(global:, file:)
          result = Homebrew::Bundle::Installer.install!(
            @dsl.entries,
            global:, file:, no_lock:, no_upgrade:, verbose:, force:, quiet:,
          )

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
