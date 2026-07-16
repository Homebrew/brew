# typed: strict
# frozen_string_literal: true

require "homebrew"
require "cli/parser"
require "extend/ENV/sensitive"

# Helper functions for commands.
module Commands
  HOMEBREW_CMD_PATH = T.let((HOMEBREW_LIBRARY_PATH/"cmd").freeze, Pathname)
  HOMEBREW_DEV_CMD_PATH = T.let((HOMEBREW_LIBRARY_PATH/"dev-cmd").freeze, Pathname)
  # If you are going to change anything in below hash,
  # be sure to also update appropriate case statement in brew.sh
  HOMEBREW_INTERNAL_COMMAND_ALIASES = T.let({
    "ls"           => "list",
    "homepage"     => "home",
    "-S"           => "search",
    "up"           => "update",
    "ln"           => "link",
    "instal"       => "install", # gem does the same
    "uninstal"     => "uninstall",
    "post_install" => "postinstall",
    "rm"           => "uninstall",
    "remove"       => "uninstall",
    "abv"          => "info",
    "dr"           => "doctor",
    "--repo"       => "--repository",
    "environment"  => "--env",
    "--config"     => "config",
    "-v"           => "--version",
    "lc"           => "livecheck",
    "tc"           => "typecheck",
    "x"            => "exec",
  }.freeze, T::Hash[String, String])
  # This pattern is used to split descriptions at full stops. We only consider a
  # dot as a full stop if it is either followed by a whitespace or at the end of
  # the description. In this way we can prevent cutting off a sentence in the
  # middle due to dots in URLs or paths.
  DESCRIPTION_SPLITTING_PATTERN = /\.(?>\s|$)/

  sig { params(cmd: String).returns(T::Boolean) }
  def self.valid_internal_cmd?(cmd)
    Homebrew.require?(HOMEBREW_CMD_PATH/cmd)
  end

  sig { params(cmd: String).returns(T::Boolean) }
  def self.valid_internal_dev_cmd?(cmd)
    Homebrew.require?(HOMEBREW_DEV_CMD_PATH/cmd)
  end

  sig { params(cmd: String).returns(T::Boolean) }
  def self.valid_ruby_cmd?(cmd)
    (valid_internal_cmd?(cmd) || valid_internal_dev_cmd?(cmd) || external_ruby_v2_cmd_path(cmd).present?) &&
      (Homebrew::AbstractCommand.command(cmd)&.ruby_cmd? == true)
  end

  sig { params(cmd: String).returns(Symbol) }
  def self.method_name(cmd)
    cmd.to_s
       .tr("-", "_")
       .downcase
       .to_sym
  end

  sig { params(cmd_path: Pathname).returns(Symbol) }
  def self.args_method_name(cmd_path)
    cmd_path_basename = basename_without_extension(cmd_path)
    cmd_method_prefix = method_name(cmd_path_basename)
    :"#{cmd_method_prefix}_args"
  end

  sig { params(cmd: String).returns(T.nilable(Pathname)) }
  def self.internal_cmd_path(cmd)
    [
      HOMEBREW_CMD_PATH/"#{cmd}.rb",
      HOMEBREW_CMD_PATH/"#{cmd}.sh",
    ].find(&:exist?)
  end

  sig { params(cmd: String).returns(T.nilable(Pathname)) }
  def self.internal_dev_cmd_path(cmd)
    [
      HOMEBREW_DEV_CMD_PATH/"#{cmd}.rb",
      HOMEBREW_DEV_CMD_PATH/"#{cmd}.sh",
    ].find(&:exist?)
  end

  # Ruby commands which can be `require`d without being run.
  sig { params(cmd: String).returns(T.nilable(Pathname)) }
  def self.external_ruby_v2_cmd_path(cmd)
    path = which("#{cmd}.rb", tap_cmd_directories)
    require_trusted_command!(path, cmd)
    path if ENV.clear_sensitive_environment! { Homebrew.require?(path) }
  end

  # Ruby commands which are run by being `require`d.
  sig { params(cmd: String).returns(T.nilable(Pathname)) }
  def self.external_ruby_cmd_path(cmd)
    path = which("brew-#{cmd}.rb", PATH.new(ENV.fetch("PATH")).append(tap_cmd_directories))
    require_trusted_command!(path, cmd)
    path
  end

  sig { params(cmd: String).returns(T.nilable(Pathname)) }
  def self.external_cmd_path(cmd)
    path = which("brew-#{cmd}", PATH.new(ENV.fetch("PATH")).append(tap_cmd_directories))
    require_trusted_command!(path, cmd)
    path
  end

  sig { params(path: T.nilable(Pathname), cmd: String).void }
  def self.require_trusted_command!(path, cmd)
    return unless path
    return if path.expand_path.ascend.none?(HOMEBREW_TAP_DIRECTORY)

    require "trust"
    Homebrew::Trust.require_trusted_command!(path, cmd)
  end

  sig { params(cmd: String).returns(T.nilable(Pathname)) }
  def self.path(cmd)
    internal_cmd = HOMEBREW_INTERNAL_COMMAND_ALIASES.fetch(cmd, cmd)
    path ||= internal_cmd_path(internal_cmd)
    path ||= internal_dev_cmd_path(internal_cmd)
    path ||= external_ruby_v2_cmd_path(cmd)
    path ||= external_ruby_cmd_path(cmd)
    path ||= external_cmd_path(cmd)
    path
  end

  sig { params(external: T::Boolean, aliases: T::Boolean).returns(T::Array[String]) }
  def self.commands(external: true, aliases: false)
    cmds = internal_commands
    cmds += internal_developer_commands
    cmds += external_commands if external
    cmds += internal_commands_aliases if aliases
    cmds.sort
  end

  sig { params(cmd: String).returns(String) }
  def self.suggestion_message(cmd)
    require "did_you_mean"

    suggestions = DidYouMean::SpellChecker.new(dictionary: commands(external: false, aliases: true)).correct(cmd)
    suggestions = DidYouMean::SpellChecker.new(dictionary: commands(aliases: true)).correct(cmd) if suggestions.empty?
    return "" if suggestions.empty?

    "\nDid you mean #{suggestions.to_sentence(two_words_connector: " or ", last_word_connector: " or ")}?"
  end

  # An array of all tap cmd directory {Pathname}s.
  sig { returns(T::Array[Pathname]) }
  def self.tap_cmd_directories
    Pathname.glob HOMEBREW_TAP_DIRECTORY/"*/*/cmd"
  end

  sig { returns(T::Array[Pathname]) }
  def self.internal_commands_paths
    find_commands HOMEBREW_CMD_PATH
  end

  sig { returns(T::Array[Pathname]) }
  def self.internal_developer_commands_paths
    find_commands HOMEBREW_DEV_CMD_PATH
  end

  sig { returns(T::Array[String]) }
  def self.internal_commands
    find_internal_commands(HOMEBREW_CMD_PATH).map(&:to_s)
  end

  sig { returns(T::Array[String]) }
  def self.internal_developer_commands
    find_internal_commands(HOMEBREW_DEV_CMD_PATH).map(&:to_s)
  end

  sig { returns(T::Array[String]) }
  def self.internal_commands_aliases
    HOMEBREW_INTERNAL_COMMAND_ALIASES.keys
  end

  sig { params(path: Pathname).returns(T::Array[String]) }
  def self.find_internal_commands(path)
    raise ArgumentError, "#{path} is not an official command path" \
      unless [HOMEBREW_CMD_PATH, HOMEBREW_DEV_CMD_PATH].include?(path)

    find_commands(path).map(&:basename)
                       .map { |basename| basename_without_extension(basename) }
                       .uniq
                       .reject { |name| Homebrew::CLI::Parser.from_cmd_path(path/"#{name}.rb")&.hide_from_man_page }
  end

  sig { returns(T::Array[String]) }
  def self.external_commands
    tap_cmd_directories.flat_map do |path|
      commands = find_commands(path).select(&:executable?)
      if path.expand_path.ascend.any?(HOMEBREW_TAP_DIRECTORY)
        require "trust"
        commands = Homebrew::Trust.trusted_command_files(commands)
      end
      commands
        .map { |basename| basename_without_extension(basename) }
        .map { |p| p.to_s.delete_prefix("brew-").strip }
    end.map(&:to_s)
       .sort
  end

  sig { params(path: Pathname).returns(String) }
  def self.basename_without_extension(path)
    path.basename(path.extname).to_s
  end

  sig { params(path: Pathname).returns(T::Array[Pathname]) }
  def self.find_commands(path)
    Pathname.glob("#{path}/*")
            .select(&:file?)
            .sort
  end

  sig { void }
  def self.rebuild_internal_commands_completion_list
    require "completions"

    cmds = internal_commands + internal_developer_commands
    cmds.reject! do |cmd|
      Homebrew::Completions::COMPLETIONS_EXCLUSION_LIST.include?(cmd) ||
        Homebrew::Completions.command_hidden_from_manpage?(cmd)
    end

    file = HOMEBREW_REPOSITORY/"completions/internal_commands_list.txt"
    file.atomic_write("#{cmds.sort.join("\n")}\n")
  end

  sig { void }
  def self.rebuild_commands_completion_list
    require "completions"

    # Ensure that the cache exists so we can build the commands list
    HOMEBREW_CACHE.mkpath

    # Don't reject `command_hidden_from_manpage?` commands here: internal ones
    # are already excluded and checking externals loads every tap command file.
    cmds = commands - Homebrew::Completions::COMPLETIONS_EXCLUSION_LIST

    all_commands_file = HOMEBREW_CACHE/"all_commands_list.txt"
    external_commands_file = HOMEBREW_CACHE/"external_commands_list.txt"
    all_commands_file.atomic_write("#{cmds.sort.join("\n")}\n")
    external_commands_file.atomic_write("#{external_commands.sort.join("\n")}\n")
  end

  sig { params(command: String, subcommand: T.nilable(String)).returns(T.nilable(T::Array[[String, String]])) }
  def self.command_options(command, subcommand: nil)
    return if command == "help"

    path = self.path(command)
    return unless path

    if (cmd_parser = Homebrew::CLI::Parser.from_cmd_path(path))
      processed_options = if subcommand.nil? && cmd_parser.subcommands.present?
        cmd_parser.processed_options_for_root_command
      else
        cmd_parser.processed_options_for_subcommand(subcommand)
      end
      processed_options.filter_map do |short, long, desc, hidden|
        next if hidden

        option = long || short
        next if option.nil?

        [option, desc]
      end
    else
      options = []
      comment_lines = path.read.lines.grep(/^#:/)
      return options if comment_lines.empty?

      # skip the comment's initial usage summary lines
      comment_lines.slice(2..-1)&.each do |line|
        match_data = / (?<option>-[-\w]+) +(?<desc>.*)$/.match(line)
        options << [match_data[:option], match_data[:desc]] if match_data
      end
      options
    end
  end

  sig { params(command: String, short: T::Boolean).returns(T.nilable(String)) }
  def self.command_description(command, short: false)
    path = self.path(command)
    return unless path

    if (cmd_parser = Homebrew::CLI::Parser.from_cmd_path(path))
      if short
        cmd_parser.description&.split(DESCRIPTION_SPLITTING_PATTERN)&.first
      else
        cmd_parser.description
      end
    else
      comment_lines = path.read.lines.grep(/^#:/)

      # skip the comment's initial usage summary lines
      comment_lines.slice(2..-1)&.each do |line|
        match_data = /^#:  (?<desc>\w.*+)$/.match(line)
        next unless match_data

        desc = match_data[:desc]
        next if desc.nil?

        return desc.split(DESCRIPTION_SPLITTING_PATTERN).first if short

        return desc
      end
      nil
    end
  end

  sig { params(command: String).returns(T::Array[Homebrew::CLI::Parser::Subcommand]) }
  def self.command_subcommands(command)
    path = self.path(command)
    return [] unless path

    cmd_parser = Homebrew::CLI::Parser.from_cmd_path(path)
    return [] if cmd_parser.blank?

    cmd_parser.subcommands
  end

  sig {
    params(command: String, subcommand: T.nilable(String))
      .returns(T.nilable(T.any(T::Array[Symbol], T::Array[String])))
  }
  def self.named_args_type(command, subcommand: nil)
    path = self.path(command)
    return unless path

    cmd_parser = Homebrew::CLI::Parser.from_cmd_path(path)
    return if cmd_parser.blank?

    args_type = if subcommand
      cmd_parser.named_args_type_for_subcommand(subcommand)
    else
      cmd_parser.named_args_type
    end
    Array(args_type)
  end

  # Returns the conflicts of a given `option` for `command`.
  sig { params(command: String, option: String).returns(T.nilable(T::Array[String])) }
  def self.option_conflicts(command, option)
    path = self.path(command)
    return unless path

    cmd_parser = Homebrew::CLI::Parser.from_cmd_path(path)
    return if cmd_parser.blank?

    hidden_options = cmd_parser.processed_options.filter_map do |short, long, _desc, hidden|
      next unless hidden

      option_name = long || short
      next unless option_name

      Homebrew::CLI::Parser.option_to_name(option_name).tr("_", "-")
    end

    cmd_parser.conflicts.map do |set|
      set = set.map { |s| s.tr "_", "-" } - hidden_options
      set - [option] if set.include? option
    end.flatten.compact
  end
end
