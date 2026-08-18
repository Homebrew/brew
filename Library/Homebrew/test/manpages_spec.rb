# typed: true
# frozen_string_literal: true

require "manpages"

RSpec.describe Homebrew::Manpages do
  before { stub_const("Cmd", Class.new(Homebrew::AbstractCommand)) }

  def subcommand_parser
    Homebrew::CLI::Parser.new(Cmd) do
      usage_banner "`test` [<subcommand>]"
      description "Test command."
      switch "--global"

      subcommand "install", default: true do
        usage_banner <<~EOS
          `test install`:
          Install dependencies.
        EOS
        switch "--force"
        named_args :none
      end

      subcommand "info" do
        usage_banner <<~EOS
          `test info` <service>:
          Show service information.
        EOS
        switch "--json"
        named_args :service, min: 1
      end
    end
  end

  it "lists options under the root command and matching subcommands", :aggregate_failures do
    manpage = described_class.cmd_parser_manpage_lines(subcommand_parser).join
    root_section, _, install_and_info_sections = manpage.partition("`test install`:")
    install_section, _, info_section = install_and_info_sections.partition("`test info` <service>:")

    expect(root_section).to include("`--global`")
    expect(root_section).not_to include("`--force`")
    expect(root_section).not_to include("`--json`")
    expect(install_section).to include("`--force`")
    expect(install_section).not_to include("`--json`")
    expect(info_section).to include("`--json`")
    expect(info_section).not_to include("`--force`")
  end

  it "does not include commands hidden from the manpage" do
    hidden_commands = %w[
      dispatch-build-bottle
      formula-analytics
      generate-analytics-api
      generate-cask-api
      generate-formula-api
      generate-internal-api
      pr-automerge
      pr-publish
      pr-pull
      pr-upload
      release
      update-license-data
      update-maintainers
      update-sponsors
    ]

    manpage = described_class.generate_cmd_manpages(
      hidden_commands.map { |command| Commands::HOMEBREW_DEV_CMD_PATH/"#{command}.rb" },
    )

    expect(manpage).not_to include(*hidden_commands)
  end
end
