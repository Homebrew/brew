# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"

module Homebrew
  module Cmd
    class Pin < AbstractCommand
      cmd_args do
        description <<~EOS
          Pin the specified <formula>, preventing them from being upgraded when
          issuing the `brew upgrade` <formula> command. See also `unpin`.

          *Note:* Other packages which depend on newer versions of a pinned formula
          might not install or run correctly.
        EOS

        named_args :installed_formula, min: 1
      end

      sig { override.void }
      def run
        args.named.to_resolved_formulae.each do |f|
          if f.pinned?
            opoo "#{f.name} already pinned"
          elsif !f.pinnable?
            ofail "#{f.name} not installed"
          else
            f.pin
          end
        end
      end
    end
  end
end
