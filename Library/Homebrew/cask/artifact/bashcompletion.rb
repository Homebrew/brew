# typed: strict
# frozen_string_literal: true

require "cask/artifact/shellcompletion"

module Cask
  module Artifact
    # Artifact corresponding to the `bash_completion` stanza.
    class BashCompletion < ShellCompletion
      # FIXME: This is a pre-existing violation
      # rubocop:disable Sorbet/AllowIncompatibleOverride
      sig { override(allow_incompatible: true).params(target: T.any(String, Pathname)).returns(Pathname) }
      # rubocop:enable Sorbet/AllowIncompatibleOverride
      def resolve_target(target)
        name = if File.extname(target).nil?
          target
        else
          new_name = File.basename(target, File.extname(target))
          odebug "Renaming completion #{target} to #{new_name}"

          new_name
        end

        config.bash_completion/name
      end
    end
  end
end
