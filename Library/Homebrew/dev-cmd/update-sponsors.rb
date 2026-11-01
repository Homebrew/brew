# typed: strict
# frozen_string_literal: true

require "utils/text"

require "abstract_command"
require "utils/github"
require "utils/sponsors"
require "system_command"
require "uri"

module Homebrew
  module DevCmd
    class UpdateSponsors < AbstractCommand
      include SystemCommand::Mixin

      cmd_args do
        description <<~EOS
          Update the list of sponsors in the `Homebrew/brew` README.
        EOS

        named_args :none

        hide_from_man_page!
      end

      sig { override.void }
      def run
        tiers = GitHub.sponsorship_tiers("Homebrew")
        odie "No sponsorship tiers found!" if tiers.empty?

        sponsorships = GitHub.sponsorships("Homebrew").map do |s|
          {
            name: s[:name], type: s[:type], monthly_amount: s[:monthly_amount],
            tier_descriptions: [s[:tier_description]] +
              Sponsors.legacy_tier_descriptions(s[:monthly_amount], s[:started_at]),
            url: "https://github.com/#{s[:login]}",
            logo: "https://github.com/#{s[:login]}.png?size=64"
          }
        end
        sponsorships.concat(Sponsors.github_one_time)
        sponsorships_by_platform = {
          "[many others](https://github.com/sponsors/Homebrew#sponsors) via " \
          "[GitHub Sponsors](https://github.com/sponsors/Homebrew)" => sponsorships,
          "[many others](https://opencollective.com/homebrew/transactions?kind=ADDED_FUNDS&kind=CONTRIBUTION) via " \
          "[Open Collective](https://opencollective.com/homebrew)"  => Sponsors.open_collective,
          "[many others](https://www.patreon.com/homebrew) via " \
          "[Patreon](https://www.patreon.com/homebrew)"             => Sponsors.patreon,
        }
        unless sponsorships_by_platform.values.flatten.any? { |s| s[:monthly_amount].positive? }
          odie "No sponsorship amounts found! Ensure you have sufficient permissions!"
        end
        named_sponsors = []
        logo_sponsors = []

        sponsorships_by_platform.each do |other_sponsors, sponsors|
          names = {}
          linked_names = {}
          sponsors.sort_by { |s| -s[:monthly_amount] }.each do |s|
            applicable_tiers = [
              *tiers,
              *s[:tier_descriptions].map { |description| { description:, monthly_amount: s[:monthly_amount] } },
            ].select do |tier|
              next false if s[:monthly_amount] < tier[:monthly_amount]

              description = tier[:description]
              description.match?(/\bREADME\b/i) &&
                (s[:type] != "Organization" || !description.match?(/\bindividuals only\b/i))
            end
            next if applicable_tiers.empty?

            escaped_name = s[:name].gsub(/[[:cntrl:]]+/, " ").strip
                                   .gsub(/[\\`*_\[\]<>&~]/) { |character| "\\#{character}" }
            names[escaped_name] ||= escaped_name

            next unless applicable_tiers.any? { |tier| tier[:description].match?(/\blogo\b/i) }

            unless [s[:logo], s[:url]].all? do |url|
              uri = URI.parse(url)
              uri.is_a?(URI::HTTPS) && uri.host.present? && !url.match?(/[[:space:]()<>\\]/)
            rescue URI::InvalidURIError
              false
            end
              opoo "Invalid logo or profile URL for #{escaped_name}."
              next
            end

            linked_names[escaped_name] = "[#{escaped_name}](#{s[:url]})"
            logo_sponsors << "[![#{escaped_name}](#{s[:logo]})](#{s[:url]})"
          end

          names = linked_names.merge(names.except(*linked_names.keys))
          named_sponsors << "- #{Utils::Text.to_sentence([*names.values, other_sponsors])}."
        end

        readme = HOMEBREW_REPOSITORY/"README.md"
        content = readme.read
        content.gsub!(/(Homebrew is generously supported by)[: ].*\Z/m) do
          "#{Regexp.last_match(1)}:\n\n#{named_sponsors.join("\n")}\n"
        end
        content << "\n<!-- release-sponsors -->\n"
        content << "#{logo_sponsors.uniq.join("\n")}\n" if logo_sponsors.present?
        content << "<!-- /release-sponsors -->\n"

        File.write(readme, content)

        diff = system_command "git", args: [
          "-C", HOMEBREW_REPOSITORY, "diff", "--exit-code", "README.md"
        ]
        if diff.status.success?
          puts "No changes to list of sponsors."
        else
          puts "List of sponsors updated in the README."
        end
      end
    end
  end
end
