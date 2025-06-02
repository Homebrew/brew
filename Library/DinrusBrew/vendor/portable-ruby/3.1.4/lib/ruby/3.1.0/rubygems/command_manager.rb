# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require_relative "command"
require_relative "user_interaction"
require_relative "text"

##
# The command manager registers and installs all the individual sub-commands
# supported by the gem command.
#
# Extra commands can be provided by writing a rubygems_plugin.rb
# file in an installed gem.  You should register your command against the
# Gem::CommandManager instance, like this:
#
#   # file rubygems_plugin.rb
#   require 'rubygems/command_manager'
#
#   Gem::CommandManager.instance.register_command :edit
#
# You should put the implementation of your command in rubygems/commands.
#
#   # file rubygems/commands/edit_command.rb
#   class Gem::Commands::EditCommand < Gem::Command
#     # ...
#   end
#
# See Gem::Command for instructions on writing gem commands.

class Gem::CommandManager
  include Gem::Text
  include Gem::UserInteraction

  BUILTIN_COMMANDS = [ # :nodoc:
    :build,
    :cert,
    :check,
    :cleanup,
    :contents,
    :dependency,
    :environment,
    :fetch,
    :generate_index,
    :help,
    :info,
    :install,
    :list,
    :lock,
    :mirror,
    :open,
    :outdated,
    :owner,
    :pristine,
    :push,
    :query,
    :rdoc,
    :search,
    :server,
    :signin,
    :signout,
    :sources,
    :specification,
    :stale,
    :uninstall,
    :unpack,
    :update,
    :which,
    :yank,
  ].freeze

  ALIAS_COMMANDS = {
    "i"      => "install",
    "login"  => "signin",
    "logout" => "signout",
  }.freeze

  ##
  # Return the authoritative instance of the command manager.

  def self.instance
    @command_manager ||= new
  end

  ##
  # Returns self. Allows a CommandManager instance to stand
  # in for the class itself.

  def instance
    self
  end

  ##
  # Reset the authoritative instance of the command manager.

  def self.reset
    @command_manager = nil
  end

  ##
  # Register all the subcommands supported by the gem command.

  def initialize
    require "timeout"
    @commands = {}

    BUILTIN_COMMANDS.each do |name|
      register_command name
    end
  end

  ##
  # Register the Symbol +command+ as a gem command.

  def register_command(command, obj=false)
    @commands[command] = obj
  end

  ##
  # Unregister the Symbol +command+ as a gem command.

  def unregister_command(command)
    @commands.delete command
  end

  ##
  # Returns a Command instance for +command_name+

  def [](command_name)
    command_name = command_name.intern
    return nil if @commands[command_name].nil?
    @commands[command_name] ||= load_and_instantiate(command_name)
  end

  ##
  # Return a sorted list of all command names as strings.

  def command_names
    @commands.keys.collect {|key| key.to_s }.sort
  end

  ##
  # Run the command specified by +args+.

  def run(args, build_args=nil)
    process_args(args, build_args)
  rescue StandardError, Timeout::Error => ex
    if ex.respond_to?(:detailed_message)
      msg = ex.detailed_message(highlight: false).sub(/\A(.*?)(?: \(.+?\))/) { $1 }
    else
      msg = ex.message
    end
    alert_error clean_text("While executing gem ... (#{ex.class})\n    #{msg}")
    ui.backtrace ex

    terminate_interaction(1)
  rescue Interrupt
    alert_error clean_text("Interrupted")
    terminate_interaction(1)
  end

  def process_args(args, build_args=nil)
    if args.empty?
      say Gem::Command::HELP
      terminate_interaction 1
    end

    case args.first
    when "-h", "--help" then
      say Gem::Command::HELP
      terminate_interaction 0
    when "-v", "--version" then
      say Gem::VERSION
      terminate_interaction 0
    when /^-/ then
      alert_error clean_text("Invalid option: #{args.first}. See 'gem --help'.")
      terminate_interaction 1
    else
      cmd_name = args.shift.downcase
      cmd = find_command cmd_name
      cmd.deprecation_warning if cmd.deprecated?
      cmd.invoke_with_build_args args, build_args
    end
  end

  def find_command(cmd_name)
    cmd_name = find_alias_command cmd_name

    possibilities = find_command_possibilities cmd_name

    if possibilities.size > 1
      raise Gem::CommandLineError,
            "Ambiguous command #{cmd_name} matches [#{possibilities.join(', ')}]"
    elsif possibilities.empty?
      raise Gem::UnknownCommandError.new(cmd_name)
    end

    self[possibilities.first]
  end

  def find_alias_command(cmd_name)
    alias_name = ALIAS_COMMANDS[cmd_name]
    alias_name ? alias_name : cmd_name
  end

  def find_command_possibilities(cmd_name)
    len = cmd_name.length

    found = command_names.select {|name| cmd_name == name[0, len] }

    exact = found.find {|name| name == cmd_name }

    exact ? [exact] : found
  end

  private

  def load_and_instantiate(command_name)
    command_name = command_name.to_s
    const_name = command_name.capitalize.gsub(/_(.)/) { $1.upcase } << "Command"
    load_error = nil

    begin
      begin
        require "rubygems/commands/#{command_name}_command"
      rescue LoadError => e
        load_error = e
      end
      Gem::Commands.const_get(const_name).new
    rescue Exception => e
      e = load_error if load_error

      alert_error clean_text("Loading command: #{command_name} (#{e.class})\n\t#{e}")
      ui.backtrace e
    end
  end
end
