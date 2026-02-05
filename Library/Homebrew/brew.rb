# typed: strict
# frozen_string_literal: true

# `HOMEBREW_STACKPROF` should be set via `brew prof --stackprof`, not manually.
if ENV["HOMEBREW_STACKPROF"]
  require "rubygems"
  require "stackprof"
  StackProf.start(mode: :wall, raw: true)
end

raise "HOMEBREW_BREW_FILE was not exported! Please call bin/brew directly!" unless ENV["HOMEBREW_BREW_FILE"]
if $PROGRAM_NAME != __FILE__ && !$PROGRAM_NAME.end_with?("/bin/ruby-prof")
  raise "#{__FILE__} must not be loaded via `require`."
end

std_trap = trap("INT") { exit! 130 } # no backtrace thanks

require_relative "global"
require "utils/output"

begin
  trap("INT", std_trap) # restore default CTRL-C handler

  if ENV["CI"]
    $stdout.sync = true
    $stderr.sync = true
  end

  empty_argv = ARGV.empty?
  help_flag_list = %w[-h --help --usage -?]
  help_flag = !ENV["HOMEBREW_HELP"].nil?
  help_cmd_index = T.let(nil, T.nilable(Integer))
  cmd = T.let(nil, T.nilable(String))

  ARGV.each_with_index do |arg, i|
    break if help_flag && cmd

    if arg == "help" && !cmd
      # Command-style help: `help <cmd>` is fine, but `<cmd> help` is not.
      help_flag = true
      help_cmd_index = i
    elsif !cmd && help_flag_list.exclude?(arg)
      require "commands"
      cmd = ARGV.delete_at(i)
      cmd = Commands::HOMEBREW_INTERNAL_COMMAND_ALIASES.fetch(cmd, cmd)
    end
  end

  ARGV.delete_at(help_cmd_index) if help_cmd_index

  require "cli/parser"
  args = Homebrew::CLI::Parser.new(Homebrew::Cmd::Brew).parse(ARGV.dup.freeze, ignore_invalid_options: true)
  Context.current = args.context

  path = PATH.new(ENV.fetch("PATH"))
  homebrew_path = PATH.new(ENV.fetch("HOMEBREW_PATH"))

  # Add shared wrappers.
  path.prepend(HOMEBREW_SHIMS_PATH/"shared")
  homebrew_path.prepend(HOMEBREW_SHIMS_PATH/"shared")

  ENV["PATH"] = path.to_s

  require "commands"
  require "warnings"

  internal_cmd = Commands.valid_internal_cmd?(cmd) || Commands.valid_internal_dev_cmd?(cmd) if cmd

  unless internal_cmd
    # Add contributed commands to PATH before checking.
    homebrew_path.append(Commands.tap_cmd_directories)

    # External commands expect a normal PATH
    ENV["PATH"] = homebrew_path.to_s
  end

  # Usage instructions should be displayed if and only if one of:
  # - a help flag is passed AND a command is matched
  # - a help flag is passed AND there is no command specified
  # - no arguments are passed
  if empty_argv || help_flag
    require "help"
    Homebrew::Help.help cmd, remaining_args: args.remaining, empty_argv:
    # `Homebrew::Help.help` never returns, except for unknown commands.
  end

  if cmd.nil?
    raise UsageError, "Unknown command: brew #{ARGV.join(" ")}"
  elsif internal_cmd || Commands.external_ruby_v2_cmd_path(cmd)
    cmd_class = Homebrew::AbstractCommand.command(cmd)
    Homebrew.running_command = cmd
    if cmd_class
      if !Homebrew::EnvConfig.no_install_from_api? && Homebrew::EnvConfig.download_concurrency > 1
        require "api"
        Homebrew::API.fetch_api_files!
      end

      command_instance = cmd_class.new

      require "utils/analytics"
      Utils::Analytics.report_command_run(command_instance)
      command_instance.run
    else
      begin
        Homebrew.public_send Commands.method_name(cmd)
      rescue NoMethodError => e
        converted_cmd = cmd.downcase.tr("-", "_")
        case_error = "undefined method `#{converted_cmd}' for module Homebrew"
        private_method_error = "private method `#{converted_cmd}' called for module Homebrew"
        Utils::Output.odie "Unknown command: brew #{cmd}" if [case_error, private_method_error].include?(e.message)

        raise
      end
    end
  elsif (path = Commands.external_ruby_cmd_path(cmd))
    Homebrew.running_command = cmd
    Homebrew.require?(path)
    exit Homebrew.failed? ? 1 : 0
  elsif Commands.external_cmd_path(cmd)
    %w[CACHE LIBRARY_PATH].each do |env|
      ENV["HOMEBREW_#{env}"] = Object.const_get(:"HOMEBREW_#{env}").to_s
    end
    exec "brew-#{cmd}", *ARGV
  else
    raise UsageError, "Unknown command: brew #{cmd}"
  end
rescue UsageError => e
  require "help"
  Homebrew::Help.help cmd, remaining_args: args&.remaining || [], usage_error: e.message
rescue SystemExit => e
  Utils::Output.onoe "Kernel.exit" if args&.debug? && !e.success?
  if args&.debug? || ARGV.include?("--debug")
    require "utils/backtrace"
    $stderr.puts Utils::Backtrace.clean(e)
  end
  raise
rescue Interrupt
  $stderr.puts # seemingly a newline is typical
  exit 130
rescue BuildError => e
  Utils::Analytics.report_build_error(e)
  e.dump(verbose: args&.verbose? || false)

  if OS.not_tier_one_configuration?
    $stderr.puts <<~EOS
      This build failure was expected, as this is not a Tier 1 configuration:
        #{Formatter.url("https://docs.brew.sh/Support-Tiers")}
      #{Formatter.bold("Do not report any issues to Homebrew/* repositories!")}
      Read the above document instead before opening any issues or PRs.
    EOS
  elsif e.formula.head? || e.formula.deprecated? || e.formula.disabled?
    reason = if e.formula.head?
      "was built from an unstable upstream --HEAD"
    elsif e.formula.deprecated?
      "is deprecated"
    elsif e.formula.disabled?
      "is disabled"
    end
    $stderr.puts <<~EOS
      #{e.formula.name}'s formula #{reason}.
      This build failure is expected behaviour.
    EOS
  end

  exit 1
rescue RuntimeError, SystemCallError => e
  raise if e.message.empty?

  Utils::Output.onoe e
  if args&.debug? || ARGV.include?("--debug")
    require "utils/backtrace"
    $stderr.puts Utils::Backtrace.clean(e)
  end

  exit 1
# Catch any other types of exceptions.
rescue Exception => e # rubocop:disable Lint/RescueException
  Utils::Output.onoe e

  method_deprecated_error = e.is_a?(MethodDeprecatedError)
  require "utils/backtrace"
  $stderr.puts Utils::Backtrace.clean(e) if args&.debug? || ARGV.include?("--debug") || !method_deprecated_error

  if OS.not_tier_one_configuration?
    $stderr.puts <<~EOS
      This error was expected, as this is not a Tier 1 configuration:
        #{Formatter.url("https://docs.brew.sh/Support-Tiers")}
      #{Formatter.bold("Do not report any issues to Homebrew/* repositories!")}
      Read the above document instead before opening any issues or PRs.
    EOS
  elsif Homebrew::EnvConfig.no_auto_update? &&
        (fetch_head = HOMEBREW_REPOSITORY/".git/FETCH_HEAD") &&
        (!fetch_head.exist? || (fetch_head.mtime.to_date < Date.today))
    $stderr.puts "#{Tty.bold}You have disabled automatic updates and have not updated today.#{Tty.reset}"
    $stderr.puts "#{Tty.bold}Do not report this issue until you've run `brew update` and tried again.#{Tty.reset}"
  elsif (issues_url = (method_deprecated_error && e.issues_url) || Utils::Backtrace.tap_error_url(e))
    $stderr.puts "If reporting this issue please do so at (not Homebrew/* repositories):"
    $stderr.puts "  #{Formatter.url(issues_url)}"
  elsif internal_cmd && !method_deprecated_error
    $stderr.puts "#{Tty.bold}Please report this issue:#{Tty.reset}"
    $stderr.puts "  #{Formatter.url(OS::ISSUES_URL)}"
  end

  exit 1
else
  exit 1 if Homebrew.failed?
ensure
  if ENV["HOMEBREW_STACKPROF"]
    StackProf.stop
    StackProf.results("prof/stackprof.dump")
  end
end
