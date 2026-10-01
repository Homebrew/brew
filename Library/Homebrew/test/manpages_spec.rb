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
    root_section, install_and_info_sections = described_class
                                              .cmd_parser_manpage_lines(subcommand_parser)
                                              .join
                                              .split("`test install`:")
    install_section, info_section = install_and_info_sections.to_s.split("`test info` <service>:")

    expect(root_section).to include("`--global`")
    expect(root_section).not_to include("`--force`")
    expect(root_section).not_to include("`--json`")
    expect(install_section).to include("`--force`")
    expect(install_section).not_to include("`--json`")
    expect(info_section).to include("`--json`")
    expect(info_section).not_to include("`--force`")
  end

  it "does not include subcommands hidden from the manpage", :aggregate_failures do
    parser = Homebrew::CLI::Parser.new(Cmd) do
      usage_banner "`test` [<subcommand>]"
      description "Test command."

      subcommand "install", default: true do
        usage_banner <<~EOS
          `test install`:
          Install dependencies.
        EOS
        named_args :none
      end

      subcommand "legacy" do
        usage_banner <<~EOS
          `test legacy`:
          Delete the legacy thing.
        EOS
        named_args :none
        hide_from_man_page!
      end
    end

    manpage = described_class.cmd_parser_manpage_lines(parser).join

    expect(manpage).to include("`test install`:")
    expect(manpage).not_to include("`test legacy`:")
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

  it "has integration test coverage for every documented command" do
    missing_commands = {
      "cmd"     => Commands.internal_commands,
      "dev-cmd" => Commands.internal_developer_commands,
    }.flat_map do |directory, commands|
      commands.reject do |command|
        spec = HOMEBREW_LIBRARY_PATH/"test/#{directory}/#{command}_spec.rb"
        spec.exist? && spec.read.match?(/:integration_test|a documented command/)
      end
    end

    expect(missing_commands).to be_empty
  end
end
