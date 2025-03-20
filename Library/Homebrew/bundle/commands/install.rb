# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    module Commands
      module Install
        module_function

        def run(global: false, file: nil, no_lock: false, no_upgrade: false, verbose: false, force: false,
                quiet: false)
          @dsl = Brewfile.read(global:, file:)
          Homebrew::Bundle::Installer.install(
            @dsl.entries,
            global:, file:, no_lock:, no_upgrade:, verbose:, force:, quiet:,
          ) || exit(1)
        end

        def dsl
          @dsl
        end
      end
    end
  end
end
