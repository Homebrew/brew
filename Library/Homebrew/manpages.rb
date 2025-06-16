# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "cli/parser"
require "erb"

module Homebrew
  # Helper functions for generating homebrew manual.
  module Manpages
    Variables = Struct.new(
      :alumni,
      :commands,
      :developer_commands,
      :environment_variables,
      :global_cask_options,
      :global_options,
      :lead,
      :maintainers,
      :official_external_commands,
      :plc,
      :tsc,
      keyword_init: true,
    )

    SOURCE_PATH = (HOMEBREW_LIBRARY_PATH/"manpages").freeze
    TARGET_MAN_PATH = (HOMEBREW_REPOSITORY/"manpages").freeze
    TARGET_DOC_PATH = (HOMEBREW_REPOSITORY/"docs").freeze

    def self.regenerate_man_pages(quiet:)
      require "kramdown"
      require "manpages/parser/ronn"
      require "manpages/converter/kramdown"
      require "manpages/converter/roff"

      markup = build_man_page(quiet:)
      root, warnings = Parser::Ronn.parse(markup)
      $stderr.puts(warnings)

      roff, warnings = Converter::Kramdown.convert(root)
      $stderr.puts(warnings)
      File.write(TARGET_DOC_PATH/"Manpage.md", roff)

      roff, warnings = Converter::Roff.convert(root)
      $stderr.puts(warnings)
      File.write(TARGET_MAN_PATH/"brew.1", roff)
    end

    def self.build_man_page(quiet:)
      template = (SOURCE_PATH/"brew.1.md.erb").read
      readme = HOMEBREW_REPOSITORY/"README.md"
      variables = Variables.new(
        commands:                   generate_cmd_manpages(Commands.internal_commands_paths),
        developer_commands:         generate_cmd_manpages(Commands.internal_developer_commands_paths),
        official_external_commands: generate_cmd_manpages(Commands.official_external_commands_paths(quiet:)),
        global_cask_options:        global_cask_options_manpage,
        global_options:             global_options_manpage,
        environment_variables:      env_vars_manpage,
        lead:                       readme.read[/(Homebrew's \[Project Leader.*\.)/, 1]
                                      .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1'),
        plc:                        readme.read[/(Homebrew's \[Project Leadership Committee.*\.)/, 1]
                                      .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1'),
        tsc:                        readme.read[/(Homebrew's \[Technical Steering Committee.*\.)/, 1]
                                      .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1'),
        maintainers:                readme.read[/(Homebrew's maintainers .*\.)/, 1]
                                      .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1'),
        alumni:                     readme.read[/(Former maintainers .*\.)/, 1]
                                      .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1'),
      )

      ERB.new(template, trim_mode: ">").result(variables.instance_eval { binding })
    end

    def self.sort_key_for_path(path)
      # Options after regular commands (`~` comes after `z` in ASCII table).
      path.basename.to_s.sub(/\.(rb|sh)$/, "").sub(/^--/, "~~")
    end

    def self.generate_cmd_manpages(cmd_paths)
      man_page_lines = []

      # preserve existing manpage order
      cmd_paths.sort_by { sort_key_for_path(_1) }
               .each do |cmd_path|
        cmd_man_page_lines = if (cmd_parser = Homebrew::CLI::Parser.from_cmd_path(cmd_path))
          next if cmd_parser.hide_from_man_page

          cmd_parser_manpage_lines(cmd_parser).join
        else
          cmd_comment_manpage_lines(cmd_path)&.join("\n")
        end
        # Convert subcommands to definition lists
        cmd_man_page_lines&.gsub!(/(?<=\n\n)([\\?\[`].+):\n/, "\\1\n\n: ")

        man_page_lines << cmd_man_page_lines
      end

      man_page_lines.compact.join("\n")
    end

    sig { params(cmd_parser: CLI::Parser).returns(T::Array[String]) }
    def self.cmd_parser_manpage_lines(cmd_parser)
      lines = [format_usage_banner(cmd_parser.usage_banner_text)]
      lines += cmd_parser.processed_options.filter_map do |short, long, desc, hidden|
        next if hidden

        if long.present?
          next if Homebrew::CLI::Parser.global_options.include?([short, long, desc])
          next if Homebrew::CLI::Parser.global_cask_options.any? do |_, option, kwargs|
                    [long, "#{long}="].include?(option) && kwargs.fetch(:description) == desc
                  end
        end

        generate_option_doc(short, long, desc)
      end
      lines
    end

    def self.cmd_comment_manpage_lines(cmd_path)
      comment_lines = cmd_path.read.lines.grep(/^#:/)
      return if comment_lines.empty?
      return if comment_lines.first.include?("@hide_from_man_page")

      lines = [format_usage_banner(comment_lines.first).chomp]
      comment_lines.slice(1..-1)
                   .each do |line|
        line = line.slice(4..-2)
        unless line
          lines.last << "\n"
          next
        end

        # Omit the common global_options documented separately in the man page.
        next if line.match?(/--(debug|help|quiet|verbose) /)

        # Format one option or a comma-separated pair of short and long options.
        line.gsub!(/^ +(-+[a-z-]+), (-+[a-z-]+) +(.*)$/, "`\\1`, `\\2`\n\n: \\3\n")
        line.gsub!(/^ +(-+[a-z-]+) +(.*)$/, "`\\1`\n\n: \\2\n")

        lines << line
      end
      lines.last << "\n"
      lines
    end

    sig { returns(String) }
    def self.global_cask_options_manpage
      lines = ["These options are applicable to the `install`, `reinstall` and `upgrade` " \
               "subcommands with the `--cask` switch.\n"]
      lines += Homebrew::CLI::Parser.global_cask_options.map do |_, long, kwargs|
        generate_option_doc(nil, long.chomp("="), kwargs.fetch(:description))
      end
      lines.join("\n")
    end

    sig { returns(String) }
    def self.global_options_manpage
      lines = ["These options are applicable across multiple subcommands.\n"]
      lines += Homebrew::CLI::Parser.global_options.map do |short, long, desc|
        generate_option_doc(short, long, desc)
      end
      lines.join("\n")
    end

    sig { returns(String) }
    def self.env_vars_manpage
      lines = Homebrew::EnvConfig::ENVS.flat_map do |env, hash|
        entry = "`#{env}`\n\n: #{hash[:description]}\n"
        default = hash[:default_text]
        default ||= "`#{hash[:default]}`." if hash[:default]
        entry += "\n\n    *Default:* #{default}\n" if default

        entry
      end
      lines.join("\n")
    end

    def self.format_opt(opt)
      "`#{opt}`" unless opt.nil?
    end

    def self.generate_option_doc(short, long, desc)
      comma = (short && long) ? ", " : ""
      <<~EOS
        #{format_opt(short)}#{comma}#{format_opt(long)}

        : #{desc}

      EOS
    end

    def self.format_usage_banner(usage_banner)
      usage_banner&.sub(/^(#: *\* )?/, "### ")
                  &.gsub(/(?<!`)\[([^\[\]]*)\](?!`)/, "\\[\\1\\]") # escape [] character (except those in code spans)
    end
  end
end
