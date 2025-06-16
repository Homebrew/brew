# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"

module Homebrew
  module Cmd
    class Unpin < AbstractCommand
      cmd_args do
        description <<~EOS
          Unpin <formula>, allowing them to be upgraded by `brew upgrade` <formula>.
          See also `pin`.
        EOS

        named_args :installed_formula, min: 1
      end

      sig { override.void }
      def run
        args.named.to_resolved_formulae.each do |f|
          if f.pinned?
            f.unpin
          elsif !f.pinnable?
            onoe "#{f.name} not installed"
          else
            opoo "#{f.name} not pinned"
          end
        end
      end
    end
  end
end
