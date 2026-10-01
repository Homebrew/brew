# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Enforces the use of `Utils::GemSetup.install_bundler_gems!` in dev-cmd.
      class InstallBundlerGems < Base
        MSG = "Only use `Utils::GemSetup.install_bundler_gems!` in dev-cmd."
        RESTRICT_ON_SEND = [:install_bundler_gems!].freeze

        sig { params(node: RuboCop::AST::Node).void }
        def on_send(node)
          file_path = processed_source.file_path
          return if file_path.match?(%r{/(dev-cmd/.+|standalone/init|startup/bootsnap)\.rb\z})

          add_offense(node)
        end
      end
    end
  end
end
