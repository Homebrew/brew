# typed: strict
# frozen_string_literal: true

require "cask/artifact/shellcompletion"

module Cask
  module Artifact
    # Artifact corresponding to the `fish_completion` stanza.
    class FishCompletion < ShellCompletion
      sig { params(target: T.any(String, Pathname)).returns(Pathname) }
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
