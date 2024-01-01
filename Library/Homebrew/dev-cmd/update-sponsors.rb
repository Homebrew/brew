# typed: true
# frozen_string_literal: true

require "cli/parser"
require "utils/github"

module Homebrew
  module_function

  NAMED_MONTHLY_AMOUNT = 100
  URL_MONTHLY_AMOUNT = 1000

  sig { returns(CLI::Parser) }
  def update_sponsors_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Update the list of GitHub Sponsors in the `Homebrew/brew` README.
      EOS

      named_args :none
    end
  end

  def sponsor_name(sponsor)
    sponsor[:name] || sponsor[:login]
  end

  def sponsor_logo(sponsor)
    "https://github.com/#{sponsor[:login]}.png?size=64"
  end

  def sponsor_url(sponsor)
    "https://github.com/#{sponsor[:login]}"
  end

  def update_sponsors
    update_sponsors_args.parse

    named_sponsors = []
    logo_sponsors = []
    # FIXME: This T.let should be unnecessary https://github.com/sorbet/sorbet/issues/6894
    largest_monthly_amount = T.let(0, T.untyped)

    GitHub.sponsorships("Homebrew").each do |s|
      largest_monthly_amount = [s[:monthly_amount], s[:closest_tier_monthly_amount]].max
      named_sponsors << "[#{sponsor_name(s)}](#{sponsor_url(s)})" if largest_monthly_amount >= NAMED_MONTHLY_AMOUNT

      next if largest_monthly_amount < URL_MONTHLY_AMOUNT

      logo_sponsors << "[![#{sponsor_name(s)}](#{sponsor_logo(s)})](#{sponsor_url(s)})"
    end

    odie "No sponsorships amounts found! Ensure you have sufficient permissions!" if largest_monthly_amount.zero?

    named_sponsors << "many other users and organisations via [GitHub Sponsors](https://github.com/sponsors/Homebrew)"

    readme = HOMEBREW_REPOSITORY/"README.md"
    content = readme.read
    content.gsub!(/(Homebrew is generously supported by) .*\Z/m, "\\1 #{named_sponsors.to_sentence}.\n")
    content << "\n#{logo_sponsors.join}\n" if logo_sponsors.presence

    File.write(readme, content)

    diff = system_command "git", args: [
      "-C", HOMEBREW_REPOSITORY, "diff", "--exit-code", "README.md"
    ]
    if diff.status.success?
      ofail "No changes to list of sponsors."
    else
      puts "List of sponsors updated in the README."
    end
  end
end
