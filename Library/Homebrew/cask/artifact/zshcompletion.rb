# typed: strict
# frozen_string_literal: true

require "cask/artifact/shellcompletion"

module Cask
  module Artifact
    # Artifact corresponding to the `zsh_completion` stanza.
    class ZshCompletion < ShellCompletion
      sig { override.params(target: T.any(String, Pathname), base_dir: T.nilable(Pathname)).returns(Pathname) }
      def resolve_target(target, base_dir: nil)
        name = if target.to_s.start_with? "_"
          target
        else
          new_name = "_#{File.basename(target, File.extname(target))}"
          odebug "Renaming completion #{target} to #{new_name}"

          new_name
        end

        config.zsh_completion/name
      end
    end
  end
end
