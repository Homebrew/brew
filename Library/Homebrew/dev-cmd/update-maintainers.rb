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
        # We assume that only public members wish to be included in the README
        public_members = GitHub.public_member_usernames("Homebrew")
        maintainers = GitHub.members_by_team("Homebrew", "maintainers")

        members = {
          plc:         GitHub.members_by_team("Homebrew", "plc"),
          tsc:         GitHub.members_by_team("Homebrew", "tsc"),
          maintainers:,
        }

        sentences = {}
        members.each do |group, hash|
          hash.replace(hash.slice(*public_members))
          hash.each { |login, name| hash[login] = "[#{name}](https://github.com/#{login})" }
          sentences[group] = hash.values.sort_by { |s| s.unicode_normalize(:nfd).gsub(/\P{L}+/, "") }.to_sentence
        end

        readme = HOMEBREW_REPOSITORY/"README.md"

        content = readme.read
        content.gsub!(/(Homebrew's \[Project Leadership Committee.*) is .*\./,
                      "\\1 is #{sentences[:plc]}.")
        content.gsub!(/(Homebrew's \[Technical Steering Committee.*) is .*\./,
                      "\\1 is #{sentences[:tsc]}.")
        content.gsub!(/(Homebrew's maintainers are).*\./,
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
