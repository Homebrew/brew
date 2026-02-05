# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "utils/github"
require "manpages"
require "system_command"

module Homebrew
  module DevCmd
    class UpdateMaintainers < AbstractCommand
      include SystemCommand::Mixin

      cmd_args do
        description <<~EOS
          Update the list of maintainers in the `Homebrew/brew` README.
        EOS

        named_args :none
      end

      sig { override.void }
      def run
        # Needed for Manpages.regenerate_man_pages below
        Homebrew.install_bundler_gems!(groups: ["man"])

        lead_maintainers = GitHub.members_by_team("Homebrew", "lead-maintainers")
        maintainers = GitHub.members_by_team("Homebrew", "maintainers")
                            .reject { |login, _| lead_maintainers.key?(login) }
        members = { lead_maintainers:, maintainers: }

        sentences = {}
        members.each do |group, hash|
          hash.each { |login, name| hash[login] = "[#{name}](https://github.com/#{login})" }
          sentences[group] = hash.values.sort_by { |s| s.unicode_normalize(:nfd).gsub(/\P{L}+/, "") }.to_sentence
        end

        readme = HOMEBREW_REPOSITORY/"README.md"

        content = readme.read
        content.gsub!(/(Homebrew's \[Lead Maintainers.* (are|is)) .*\./,
                      "\\1 #{sentences[:lead_maintainers]}.")
        content.gsub!(/(Homebrew's other Maintainers (are|is)) .*\./,
                      "\\1 #{sentences[:maintainers]}.")

        File.write(readme, content)

        diff = system_command "git", args: ["-C", HOMEBREW_REPOSITORY, "diff", "--exit-code", "README.md"]
        if diff.status.success?
          ofail "No changes to list of maintainers."
        else
          Manpages.regenerate_man_pages(quiet: true)
          puts "List of maintainers updated in the README and the generated man pages."
        end
      end
    end
  end
end
