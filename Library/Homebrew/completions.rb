# typed: strict
# frozen_string_literal: true

require "utils/output"

require "utils/link"
require "settings"
require "erb"
require "tap"

module Homebrew
  # Helper functions for generating shell completions.
  module Completions
    extend Utils::Output::Mixin

    Variables = Struct.new(
      :aliases,
      :builtin_command_descriptions,
      :completion_functions,
      :maintainer_descriptions,
      :maintainer_commands,
      :function_mappings,
    )

    COMPLETIONS_DIR = T.let((HOMEBREW_REPOSITORY/"completions").freeze, Pathname)
    TEMPLATE_DIR = T.let((HOMEBREW_LIBRARY_PATH/"completions").freeze, Pathname)

    SHELLS = %w[bash fish zsh].freeze
    COMPLETIONS_EXCLUSION_LIST = %w[
      instal
      uninstal
      update-report
    ].freeze

    BASH_NAMED_ARGS_COMPLETION_FUNCTION_MAPPING = T.let({
      formula:           "__brew_complete_formulae",
      installed_formula: "__brew_complete_installed_formulae",
      outdated_formula:  "__brew_complete_outdated_formulae",
      cask:              "__brew_complete_casks",
      installed_cask:    "__brew_complete_installed_casks",
      outdated_cask:     "__brew_complete_outdated_casks",
      tap:               "__brew_complete_tapped",
      installed_tap:     "__brew_complete_tapped",
      command:           "__brew_complete_commands",
      diagnostic_check:  '__brewcomp "${__HOMEBREW_DOCTOR_CHECKS=$(brew doctor --list-checks)}"',
      file:              "__brew_complete_files",
      service:           "__brew_complete_services",
    }.freeze, T::Hash[Symbol, String])

    ZSH_NAMED_ARGS_COMPLETION_FUNCTION_MAPPING = T.let({
      formula:           "__brew_formulae",
      installed_formula: "__brew_installed_formulae",
      outdated_formula:  "__brew_outdated_formulae",
      cask:              "__brew_casks",
      installed_cask:    "__brew_installed_casks",
      outdated_cask:     "__brew_outdated_casks",
      tap:               "__brew_any_tap",
      installed_tap:     "__brew_installed_taps",
      command:           "__brew_commands",
      diagnostic_check:  "__brew_diagnostic_checks",
      file:              "__brew_formulae_or_ruby_files",
      service:           "__brew_services",
    }.freeze, T::Hash[Symbol, String])

    FISH_NAMED_ARGS_COMPLETION_FUNCTION_MAPPING = T.let({
      formula:           "__fish_brew_suggest_formulae_all",
      installed_formula: "__fish_brew_suggest_formulae_installed",
      outdated_formula:  "__fish_brew_suggest_formulae_outdated",
      cask:              "__fish_brew_suggest_casks_all",
      installed_cask:    "__fish_brew_suggest_casks_installed",
      outdated_cask:     "__fish_brew_suggest_casks_outdated",
      tap:               "__fish_brew_suggest_taps_installed",
      installed_tap:     "__fish_brew_suggest_taps_installed",
      command:           "__fish_brew_suggest_commands",
      diagnostic_check:  "__fish_brew_suggest_diagnostic_checks",
      service:           "__fish_brew_suggest_services",
    }.freeze, T::Hash[Symbol, String])

    sig { void }
    def self.link!
      Settings.write :linkcompletions, true
      Tap.installed.each do |tap|
        Utils::Link.link_completions tap.path, "brew completions link"
      end
    end

    sig { void }
    def self.unlink!
      Settings.write :linkcompletions, false
      Tap.installed.each do |tap|
        next if tap.official_git_checkout?

        Utils::Link.unlink_completions tap.path
      end
    end

    sig { returns(T::Boolean) }
    def self.link_completions?
      Settings.read(:linkcompletions) == "true"
    end

    sig { returns(T::Boolean) }
    def self.completions_to_link?
      Tap.installed.each do |tap|
        next if tap.official_git_checkout?

        SHELLS.each do |shell|
          return true if (tap.path/"completions/#{shell}").exist?
        end
      end

      false
    end

    sig { void }
    def self.show_completions_message_if_needed
      return if Settings.read(:completionsmessageshown) == "true"
      return unless completions_to_link?

      ohai "Homebrew completions for external commands are unlinked by default!"
      puts <<~EOS
        To opt-in to automatically linking external tap shell completion files, run:
          brew completions link
        Then, follow the directions at #{Formatter.url("https://docs.brew.sh/Shell-Completion")}
      EOS

      Settings.write :completionsmessageshown, true
    end

    sig { void }
    def self.update_shell_completions!
      commands = (Commands.internal_commands_paths + Commands.internal_developer_commands_paths)
                 .map { |path| Commands.basename_without_extension(path) }
                 .uniq
                 .sort

      puts "Writing completions to #{COMPLETIONS_DIR}"

      (COMPLETIONS_DIR/"bash/brew").atomic_write generate_bash_completion_file(commands)
      (COMPLETIONS_DIR/"zsh/_brew").atomic_write generate_zsh_completion_file(commands)
      (COMPLETIONS_DIR/"fish/brew.fish").atomic_write generate_fish_completion_file(commands)
    end

    sig { params(command: String).returns(T::Boolean) }
    def self.command_gets_completions?(command)
      command_options(command).any? || Commands.command_subcommands(command).any?
    end

    sig { params(command: String).returns(T::Boolean) }
    def self.command_hidden_from_manpage?(command)
      return false unless (cmd_path = Commands.path(command))

      Homebrew::CLI::Parser.from_cmd_path(cmd_path)&.hide_from_man_page == true
    end

    sig { params(command: String).returns(T.nilable(String)) }
    def self.zsh_command_description(command)
      description = Commands.command_description(command, short: true)
      return if description.blank?

      "'#{command}:#{format_description(description)}'"
    end

    sig { params(subcommands: T::Array[Homebrew::CLI::Parser::Subcommand]).returns(T::Array[String]) }
    def self.subcommand_completion_names(subcommands)
      subcommands.flat_map { |subcommand| [subcommand.name, *subcommand.aliases] }
    end

    sig { params(description: String, fish: T::Boolean).returns(String) }
    def self.format_description(description, fish: false)
      description = if fish
        description.gsub("'", "\\\\'")
      else
        description.gsub("'", "'\\\\''")
      end
      description.gsub(/[<>]/, "").tr("\n", " ").chomp(".")
    end

    sig { params(command: String, subcommand: T.nilable(String)).returns(T::Hash[String, String]) }
    def self.command_options(command, subcommand: nil)
      options = {}
      Commands.command_options(command, subcommand:)&.each do |option|
        next if option.blank?

        name = option.first
        desc = option.second
        if name.start_with? "--[no-]"
          options[name.gsub("[no-]", "")] = desc
          options[name.sub("[no-]", "no-")] = desc
        else
          options[name] = desc
        end
      end
      options
    end

    sig { params(types: T.nilable(T::Array[T.any(Symbol, String)])).returns(String) }
    def self.generate_bash_named_args_completion(types)
      named_completion_string = ""
      return named_completion_string if types.blank?

      named_args_strings, named_args_types = types.partition { |type| type.is_a? String }

      T.cast(named_args_types, T::Array[Symbol]).each do |type|
        next unless BASH_NAMED_ARGS_COMPLETION_FUNCTION_MAPPING.key? type

        named_completion_string += "\n  #{BASH_NAMED_ARGS_COMPLETION_FUNCTION_MAPPING[type]}"
      end

      named_completion_string += "\n  __brewcomp \"#{named_args_strings.join(" ")}\"" if named_args_strings.any?
      named_completion_string
    end

    sig { params(command: String, subcommands: T::Array[Homebrew::CLI::Parser::Subcommand]).returns(String) }
    def self.generate_bash_nested_subcommand_completion(command, subcommands)
      top_level_options = command_options(command).keys.sort.join("\n          ")
      subcommand_names = subcommand_completion_names(subcommands).join(" ")
      subcommand_cases = subcommands.map do |subcommand|
        "      #{([subcommand.name] + subcommand.aliases).join("|")}) subcommand=\"#{subcommand.name}\"; break ;;"
      end.join("\n")
      option_cases = subcommands.map do |subcommand|
        options = command_options(command, subcommand: subcommand.name).keys.sort.join("\n        ")
        <<~EOS
          #{subcommand.name})
                  __brewcomp "
                  #{options}
                  "
                  return
                  ;;
        EOS
      end.join
      named_arg_cases = subcommands.filter_map do |subcommand|
        named_completion_string = generate_bash_named_args_completion(
          Commands.named_args_type(command, subcommand: subcommand.name),
        )
        next if named_completion_string.blank?

        <<~EOS
          #{subcommand.name})#{named_completion_string}
                  ;;
        EOS
      end.join

      <<~COMPLETION
        _brew_#{Commands.method_name command}() {
          local cur="${COMP_WORDS[COMP_CWORD]}"
          local subcommand=""
          local i
          for (( i = 2; i < COMP_CWORD; i++ ))
          do
            case "${COMP_WORDS[i]}" in
        #{subcommand_cases}
              *) ;;
            esac
          done
          case "${cur}" in
            -*)
              case "${subcommand}" in
                "")
                  __brewcomp "
                  #{top_level_options}
                  "
                  return
                  ;;
        #{option_cases.chomp}
                *) ;;
              esac
              ;;
            *) ;;
          esac
          case "${subcommand}" in
            "")
              __brewcomp "#{subcommand_names}"
              ;;
        #{named_arg_cases.chomp}
            *) ;;
          esac
        }
      COMPLETION
    end

    sig { params(command: String).returns(T.nilable(String)) }
    def self.generate_bash_subcommand_completion(command)
      return unless command_gets_completions? command

      subcommands = Commands.command_subcommands(command)
      return generate_bash_nested_subcommand_completion(command, subcommands) if subcommands.present?

      named_completion_string = generate_bash_named_args_completion(Commands.named_args_type(command))

      <<~COMPLETION
        _brew_#{Commands.method_name command}() {
          local cur="${COMP_WORDS[COMP_CWORD]}"
          case "${cur}" in
            -*)
              __brewcomp "
              #{command_options(command).keys.sort.join("\n      ")}
              "
              return
              ;;
            *) ;;
          esac#{named_completion_string}
        }
      COMPLETION
    end

    sig { params(commands: T::Array[String]).returns(String) }
    def self.generate_bash_completion_file(commands)
      commands -= Commands.internal_commands_aliases

      variables = Variables.new(
        aliases:              Commands::HOMEBREW_INTERNAL_COMMAND_ALIASES.map do |alias_cmd, command|
          "#{alias_cmd}) echo \"#{command}\" ;;"
        end,
        completion_functions: commands.filter_map do |command|
          generate_bash_subcommand_completion command
        end,
        maintainer_commands:  commands.select { |command| command_hidden_from_manpage?(command) },
        function_mappings:    commands.filter_map do |command|
          next unless command_gets_completions? command

          "#{command}) _brew_#{Commands.method_name command} ;;"
        end,
      )

      ERB.new((TEMPLATE_DIR/"bash.erb").read, trim_mode: ">").result(variables.instance_eval { binding })
    end

    sig { params(opt: String).returns(String) }
    def self.format_zsh_argument(opt)
      if opt.start_with?("- ")
        opt
      else
        "'#{opt}'"
      end
    end

    sig { params(command: String).returns(T.nilable(String)) }
    def self.generate_zsh_subcommand_completion(command)
      return unless command_gets_completions? command

      subcommands = Commands.command_subcommands(command)
      return generate_zsh_nested_subcommand_completion(command, subcommands) if subcommands.present?

      options = command_options(command)
      options = generate_zsh_arguments(command, options, Commands.named_args_type(command))

      <<~COMPLETION
        # brew #{command}
        _brew_#{Commands.method_name command}() {
          _arguments \\
            #{options.map! { |opt| format_zsh_argument(opt) }.join(" \\\n    ")}
        }
      COMPLETION
    end

    sig {
      params(
        command: String,
        options: T::Hash[String, String],
        types:   T.nilable(T::Array[T.any(Symbol, String)]),
      ).returns(T::Array[String])
    }
    def self.generate_zsh_arguments(command, options, types)
      options = options.dup

      args_options = []
      if types
        named_args_strings, named_args_types = types.partition { |type| type.is_a? String }

        T.cast(named_args_types, T::Array[Symbol]).each do |type|
          next unless ZSH_NAMED_ARGS_COMPLETION_FUNCTION_MAPPING.key? type

          args_options << "- #{type}"
          opt = "--#{type.to_s.gsub(/(?:installed|outdated)_/, "")}"
          if options.key?(opt)
            desc = options[opt]

            if desc.blank?
              args_options << opt
            else
              conflicts = generate_zsh_option_exclusions(command, opt)
              args_options << "#{conflicts}#{opt}[#{format_description desc}]"
            end

            options.delete(opt)
          end
          args_options << "*:#{type}:#{ZSH_NAMED_ARGS_COMPLETION_FUNCTION_MAPPING[type]}"
        end

        if named_args_strings.any?
          args_options << "- subcommand"
          args_options << "*:subcommand:(#{named_args_strings.join(" ")})"
        end
      end

      options = options.sort.map do |opt, desc|
        next opt if desc.blank?

        conflicts = generate_zsh_option_exclusions(command, opt)
        "#{conflicts}#{opt}[#{format_description desc}]"
      end
      options += args_options

      options
    end

    sig { params(command: String, subcommands: T::Array[Homebrew::CLI::Parser::Subcommand]).returns(String) }
    def self.generate_zsh_nested_subcommand_completion(command, subcommands)
      top_level_arguments = generate_zsh_arguments(
        command,
        command_options(command),
        nil,
      ).map { |opt| format_zsh_argument(opt) } + [
        "'1:subcommand:->subcommand'",
        "'*::arg:->args'",
      ]
      subcommand_descriptions = subcommands.flat_map do |subcommand|
        description = subcommand.description
        ([subcommand.name] + subcommand.aliases).map do |subcommand_name|
          if description.present?
            "'#{subcommand_name}:#{format_description(description)}'"
          else
            "'#{subcommand_name}'"
          end
        end
      end.join("\n    ")

      subcommand_cases = subcommands.map do |subcommand|
        names = ([subcommand.name] + subcommand.aliases).join("|")
        options = generate_zsh_arguments(
          command,
          command_options(command, subcommand: subcommand.name),
          Commands.named_args_type(command, subcommand: subcommand.name),
        )
        <<~EOS
          #{names})
                  _arguments \\
                    #{options.map! { |opt| format_zsh_argument(opt) }.join(" \\\n          ")}
                  ;;
        EOS
      end.join

      <<~COMPLETION
        # brew #{command}
        _brew_#{Commands.method_name command}() {
          local state
          local -a subcommands
          subcommands=(
            #{subcommand_descriptions}
          )

          _arguments -C \\
            #{top_level_arguments.join(" \\\n    ")}

          case "$state" in
            subcommand)
              _describe -t subcommands 'subcommand' subcommands
              ;;
            args)
              case "$words[1]" in
        #{subcommand_cases.chomp}
                *) ;;
              esac
              ;;
          esac
        }
      COMPLETION
    end

    sig { params(command: String, option: String).returns(String) }
    def self.generate_zsh_option_exclusions(command, option)
      conflicts = Commands.option_conflicts(command, option.gsub(/^--?/, ""))
      return "" if conflicts.blank?

      "(#{conflicts.map { |conflict| "-#{"-" if conflict.size > 1}#{conflict}" }.join(" ")})"
    end

    sig { params(commands: T::Array[String]).returns(String) }
    def self.generate_zsh_completion_file(commands)
      commands -= Commands.internal_commands_aliases

      variables = Variables.new(
        aliases:                      Commands::HOMEBREW_INTERNAL_COMMAND_ALIASES.filter_map do |alias_cmd, command|
          alias_cmd = "'#{alias_cmd}'" if alias_cmd.start_with? "-"
          command = "'#{command}'" if command.start_with? "-"
          "#{alias_cmd} #{command}"
        end,

        builtin_command_descriptions: commands.filter_map do |command|
          next if Commands::HOMEBREW_INTERNAL_COMMAND_ALIASES.key? command
          next if command_hidden_from_manpage?(command)

          zsh_command_description(command)
        end,

        maintainer_descriptions:      commands.filter_map do |command|
          next unless command_hidden_from_manpage?(command)

          zsh_command_description(command)
        end,

        completion_functions:         commands.filter_map do |command|
          generate_zsh_subcommand_completion command
        end,
      )

      ERB.new((TEMPLATE_DIR/"zsh.erb").read, trim_mode: ">").result(variables.instance_eval { binding })
    end

    sig { params(command: String).returns(T.nilable(String)) }
    def self.generate_fish_subcommand_completion(command)
      command_description = format_description Commands.command_description(command, short: true).to_s, fish: true
      lines = if COMPLETIONS_EXCLUSION_LIST.include?(command) ||
                 Commands::HOMEBREW_INTERNAL_COMMAND_ALIASES.key?(command)
        []
      elsif command_hidden_from_manpage?(command)
        ["complete -f -c brew -n 'not __fish_brew_command; and set -q HOMEBREW_DEVELOPER' " \
         "-a '#{command}' -d '#{command_description}'"]
      else
        ["__fish_brew_complete_cmd '#{command}' '#{command_description}'"]
      end
      return unless command_gets_completions? command

      subcommands = Commands.command_subcommands(command)
      return generate_fish_nested_subcommand_completion(command, subcommands) if subcommands.present?

      options = command_options(command).sort.filter_map do |opt, desc|
        arg_line = "__fish_brew_complete_arg '#{command}' -l #{opt.sub(/^-+/, "")}"
        arg_line += " -d '#{format_description desc, fish: true}'" if desc.present?
        arg_line
      end

      subcommands = []
      named_args = []
      if (types = Commands.named_args_type(command))
        named_args_strings, named_args_types = types.partition { |type| type.is_a? String }

        T.cast(named_args_types, T::Array[Symbol]).each do |type|
          next unless FISH_NAMED_ARGS_COMPLETION_FUNCTION_MAPPING.key? type

          named_arg_function = FISH_NAMED_ARGS_COMPLETION_FUNCTION_MAPPING[type]
          named_arg_prefix = "__fish_brew_complete_arg '#{command}; and not __fish_seen_argument"

          formula_option = command_options(command).key?("--formula")
          cask_option = command_options(command).key?("--cask")

          named_args << if formula_option && cask_option && type.to_s.end_with?("formula")
            "#{named_arg_prefix} -l cask -l casks' -a '(#{named_arg_function})'"
          elsif formula_option && cask_option && type.to_s.end_with?("cask")
            "#{named_arg_prefix} -l formula -l formulae' -a '(#{named_arg_function})'"
          else
            "__fish_brew_complete_arg '#{command}' -a '(#{named_arg_function})'"
          end
        end

        named_args_strings.each do |subcommand|
          subcommands << "__fish_brew_complete_sub_cmd '#{command}' '#{subcommand}'"
        end
      end

      lines += subcommands + options + named_args
      <<~COMPLETION
        #{lines.join("\n").chomp}
      COMPLETION
    end

    sig {
      params(command: String, types: T.nilable(T::Array[T.any(Symbol, String)]),
             subcommand: T.nilable(String)).returns(T::Array[String])
    }
    def self.generate_fish_named_args(command, types, subcommand: nil)
      named_args = []
      return named_args if types.blank?

      named_args_strings, named_args_types = types.partition { |type| type.is_a? String }

      T.cast(named_args_types, T::Array[Symbol]).each do |type|
        next unless FISH_NAMED_ARGS_COMPLETION_FUNCTION_MAPPING.key? type

        named_arg_function = FISH_NAMED_ARGS_COMPLETION_FUNCTION_MAPPING[type]
        if subcommand
          named_args << "__fish_brew_complete_sub_arg '#{command}' '#{subcommand}' -a '(#{named_arg_function})'"
          next
        end

        named_arg_prefix = "__fish_brew_complete_arg '#{command}; and not __fish_seen_argument"

        formula_option = command_options(command).key?("--formula")
        cask_option = command_options(command).key?("--cask")

        named_args << if formula_option && cask_option && type.to_s.end_with?("formula")
          "#{named_arg_prefix} -l cask -l casks' -a '(#{named_arg_function})'"
        elsif formula_option && cask_option && type.to_s.end_with?("cask")
          "#{named_arg_prefix} -l formula -l formulae' -a '(#{named_arg_function})'"
        else
          "__fish_brew_complete_arg '#{command}' -a '(#{named_arg_function})'"
        end
      end

      return named_args if subcommand

      named_args_strings.map do |named_arg_string|
        "__fish_brew_complete_sub_cmd '#{command}' '#{named_arg_string}'"
      end + named_args
    end

    sig { params(command: String, subcommands: T::Array[Homebrew::CLI::Parser::Subcommand]).returns(String) }
    def self.generate_fish_nested_subcommand_completion(command, subcommands)
      command_description = format_description Commands.command_description(command, short: true).to_s, fish: true
      lines = if COMPLETIONS_EXCLUSION_LIST.include?(command) ||
                 Commands::HOMEBREW_INTERNAL_COMMAND_ALIASES.key?(command)
        []
      else
        ["__fish_brew_complete_cmd '#{command}' '#{command_description}'"]
      end

      subcommands.each do |subcommand|
        description = subcommand.description
        ([subcommand.name] + subcommand.aliases).each do |subcommand_name|
          line = "__fish_brew_complete_sub_cmd '#{command}' '#{subcommand_name}'"
          line += " '#{format_description(description, fish: true)}'" if description.present?
          lines << line
        end
      end

      lines += command_options(command).sort.filter_map do |opt, desc|
        arg_line = "__fish_brew_complete_arg '#{command}; and [ (count (__fish_brew_args)) = 1 ]' " \
                   "-l #{opt.sub(/^-+/, "")}"
        arg_line += " -d '#{format_description desc, fish: true}'" if desc.present?
        arg_line
      end

      subcommands.each do |subcommand|
        subcommand_names = ([subcommand.name] + subcommand.aliases).join(" ")
        lines += command_options(command, subcommand: subcommand.name).sort.filter_map do |opt, desc|
          arg_line = "__fish_brew_complete_sub_arg '#{command}' '#{subcommand_names}' " \
                     "-l #{opt.sub(/^-+/, "")}"
          arg_line += " -d '#{format_description desc, fish: true}'" if desc.present?
          arg_line
        end
        lines += generate_fish_named_args(
          command,
          Commands.named_args_type(command, subcommand: subcommand.name),
          subcommand: subcommand_names,
        )
      end

      <<~COMPLETION
        #{lines.join("\n").chomp}
      COMPLETION
    end

    sig { params(commands: T::Array[String]).returns(String) }
    def self.generate_fish_completion_file(commands)
      commands -= Commands.internal_commands_aliases

      variables = Variables.new(
        aliases:              Commands::HOMEBREW_INTERNAL_COMMAND_ALIASES.map do |alias_cmd, command|
          "        case '#{alias_cmd}'\n            echo '#{command}'"
        end,
        completion_functions: commands.filter_map do |command|
          generate_fish_subcommand_completion command
        end,
      )

      ERB.new((TEMPLATE_DIR/"fish.erb").read, trim_mode: ">").result(variables.instance_eval { binding })
    end
  end
end
