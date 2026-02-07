# typed: strict
# frozen_string_literal: true

require "cask/artifact/shellcompletion"

module Cask
  module Artifact
    # Artifact corresponding to the `fish_completion` stanza.
    class FishCompletion < ShellCompletion
      # FIXME: This is a pre-existing violation
      # rubocop:disable Sorbet/AllowIncompatibleOverride
      sig { override(allow_incompatible: true).params(target: T.any(String, Pathname)).returns(Pathname) }
      # rubocop:enable Sorbet/AllowIncompatibleOverride
      def resolve_target(target)
        name = if target.to_s.end_with? ".fish"
          target
        else
          new_name = "#{File.basename(target, File.extname(target))}.fish"
          odebug "Renaming completion #{target} to #{new_name}"

          new_name
        end

        config.fish_completion/name
      end
    end
  end
end
