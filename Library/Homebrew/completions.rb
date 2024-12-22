# typed: strict
# frozen_string_literal: true

require "utils/link"
require "settings"
require "erb"

module Homebrew
  # Helper functions for generating shell completions.
  module Completions
    Variables = Struct.new(
      :aliases,
      :builtin_command_descriptions,
      :completion_functions,
      :function_mappings,
      keyword_init: true,
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
        next if tap.official?

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
        next if tap.official?

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
      commands = Commands.commands(external: false, aliases: true).sort

      puts "Writing completions to #{COMPLETIONS_DIR}"

      (COMPLETIONS_DIR/"bash/brew").atomic_write generate_bash_completion_file(commands)
      (COMPLETIONS_DIR/"zsh/_brew").atomic_write generate_zsh_completion_file(commands)
      (COMPLETIONS_DIR/"fish/brew.fish").atomic_write generate_fish_completion_file(commands)
    end

    sig { params(command: String).returns(T::Boolean) }
    def self.command_gets_completions?(command)
      command_options(command).any?
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

    sig { params(command: String).returns(T::Hash[String, String]) }
    def self.command_options(command)
      options = {}
      Commands.command_options(command)&.each do |option|
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

    sig { params(command: String).returns(T.nilable(String)) }
    def self.generate_bash_subcommand_completion(command)
      return unless command_gets_completions? command

      named_completion_string = ""
      if (types = Commands.named_args_type(command))
        named_args_strings, named_args_types = types.partition { |type| type.is_a? String }

        named_args_types.each do |type|
          next unless BASH_NAMED_ARGS_COMPLETION_FUNCTION_MAPPING.key? type

          named_completion_string += "\n  #{BASH_NAMED_ARGS_COMPLETION_FUNCTION_MAPPING[type]}"
        end

        named_completion_string += "\n  __brewcomp \"#{named_args_strings.join(" ")}\"" if named_args_strings.any?
      end

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
      variables = Variables.new(
        completion_functions: commands.filter_map do |command|
          generate_bash_subcommand_completion command
        end,
        function_mappings:    commands.filter_map do |command|
          next unless command_gets_completions? command

          "#{command}) _brew_#{Commands.method_name command} ;;"
        end,
      )

      ERB.new((TEMPLATE_DIR/"bash.erb").read, trim_mode: ">").result(variables.instance_eval { binding })
    end

    sig { params(command: String).returns(T.nilable(String)) }
    def self.generate_zsh_subcommand_completion(command)
      return unless command_gets_completions? command

      options = command_options(command)

      args_options = []
      if (types = Commands.named_args_type(command))
        named_args_strings, named_args_types = types.partition { |type| type.is_a? String }

        named_args_types.each do |type|
          next unless ZSH_NAMED_ARGS_COMPLETION_FUNCTION_MAPPING.key? type

          args_options << "- #{type}"
          opt = "--#{type.to_s.gsub(/(installed|outdated)_/, "")}"
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
          args_options << "*::#{type}:#{ZSH_NAMED_ARGS_COMPLETION_FUNCTION_MAPPING[type]}"
        end

        if named_args_strings.any?
          args_options << "- subcommand"
          args_options << "*::subcommand:(#{named_args_strings.join(" ")})"
        end
      end

      options = options.sort.map do |opt, desc|
        next opt if desc.blank?

        conflicts = generate_zsh_option_exclusions(command, opt)
        "#{conflicts}#{opt}[#{format_description desc}]"
      end
      options += args_options

      <<~COMPLETION
        # brew #{command}
        _brew_#{Commands.method_name command}() {
          _arguments \\
            #{options.map! { |opt| opt.start_with?("- ") ? opt : "'#{opt}'" }.join(" \\\n    ")}
        }
      COMPLETION
    end

    sig { params(command: String, option: String).returns(String) }
    def self.generate_zsh_option_exclusions(command, option)
      conflicts = Commands.option_conflicts(command, option.gsub(/^--?/, ""))
      return "" unless conflicts.presence

      "(#{conflicts.map { |conflict| "-#{"-" if conflict.size > 1}#{conflict}" }.join(" ")})"
    end

    sig { params(commands: T::Array[String]).returns(String) }
    def self.generate_zsh_completion_file(commands)
      variables = Variables.new(
        aliases:                      Commands::HOMEBREW_INTERNAL_COMMAND_ALIASES.filter_map do |alias_cmd, command|
          alias_cmd = "'#{alias_cmd}'" if alias_cmd.start_with? "-"
          command = "'#{command}'" if command.start_with? "-"
          "#{alias_cmd} #{command}"
        end,

        builtin_command_descriptions: commands.filter_map do |command|
          next if Commands::HOMEBREW_INTERNAL_COMMAND_ALIASES.key? command

          description = Commands.command_description(command, short: true)
          next if description.blank?

          description = format_description description
          "'#{command}:#{description}'"
        end,

        completion_functions:         commands.filter_map do |command|
          generate_zsh_subcommand_completion command
        end,
      )

      ERB.new((TEMPLATE_DIR/"zsh.erb").read, trim_mode: ">").result(variables.instance_eval { binding })
    end

    sig { params(command: String).returns(T.nilable(String)) }
    def self.generate_fish_subcommand_completion(command)
      return unless command_gets_completions? command

      command_description = format_description Commands.command_description(command, short: true), fish: true
      lines = if COMPLETIONS_EXCLUSION_LIST.include?(command)
        []
      else
        ["__fish_brew_complete_cmd '#{command}' '#{command_description}'"]
      end

      options = command_options(command).sort.filter_map do |opt, desc|
        arg_line = "__fish_brew_complete_arg '#{command}' -l #{opt.sub(/^-+/, "")}"
        arg_line += " -d '#{format_description desc, fish: true}'" if desc.present?
        arg_line
      end

      subcommands = []
      named_args = []
      if (types = Commands.named_args_type(command))
        named_args_strings, named_args_types = types.partition { |type| type.is_a? String }

        named_args_types.each do |type|
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

    sig { params(commands: T::Array[String]).returns(String) }
    def self.generate_fish_completion_file(commands)
      variables = Variables.new(
        completion_functions: commands.filter_map do |command|
          generate_fish_subcommand_completion command
        end,
      )

      ERB.new((TEMPLATE_DIR/"fish.erb").read, trim_mode: ">").result(variables.instance_eval { binding })
    end
  end
end
