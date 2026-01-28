# typed: strict
# frozen_string_literal: true

require "cask/artifact/shellcompletion"

module Cask
  module Artifact
    # Artifact corresponding to the `bash_completion` stanza.
    class BashCompletion < ShellCompletion
      sig { params(target: T.any(String, Pathname)).returns(Pathname) }
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
