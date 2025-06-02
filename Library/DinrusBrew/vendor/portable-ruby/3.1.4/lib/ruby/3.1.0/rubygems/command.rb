# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require_relative "optparse"
require_relative "requirement"
require_relative "user_interaction"

##
# Base class for all Gem commands.  When creating a new gem command, define
# #initialize, #execute, #arguments, #defaults_str, #description and #usage
# (as appropriate).  See the above mentioned methods for details.
#
# A very good example to look at is Gem::Commands::ContentsCommand

class Gem::Command
  include Gem::UserInteraction

  Gem::OptionParser.accept Symbol do |value|
    value.to_sym
  end

  ##
  # The name of the command.

  attr_reader :command

  ##
  # The options for the command.

  attr_reader :options

  ##
  # The default options for the command.

  attr_accessor :defaults

  ##
  # The name of the command for command-line invocation.

  attr_accessor :program_name

  ##
  # A short description of the command.

  attr_accessor :summary

  ##
  # Arguments used when building gems

  def self.build_args
    @build_args ||= []
  end

  def self.build_args=(value)
    @build_args = value
  end

  def self.common_options
    @common_options ||= []
  end

  def self.add_common_option(*args, &handler)
    Gem::Command.common_options << [args, handler]
  end

  def self.extra_args
    @extra_args ||= []
  end

  def self.extra_args=(value)
    case value
    when Array
      @extra_args = value
    when String
      @extra_args = value.split(" ")
    end
  end

  ##
  # Return an array of extra arguments for the command.  The extra arguments
  # come from the gem configuration file read at program startup.

  def self.specific_extra_args(cmd)
    specific_extra_args_hash[cmd]
  end

  ##
  # Add a list of extra arguments for the given command.  +args+ may be an
  # array or a string to be split on white space.

  def self.add_specific_extra_args(cmd,args)
    args = args.split(/\s+/) if args.kind_of? String
    specific_extra_args_hash[cmd] = args
  end

  ##
  # Accessor for the specific extra args hash (self initializing).

  def self.specific_extra_args_hash
    @specific_extra_args_hash ||= Hash.new do |h,k|
      h[k] = Array.new
    end
  end

  ##
  # Initializes a generic gem command named +command+.  +summary+ is a short
  # description displayed in `gem help commands`.  +defaults+ are the default
  # options.  Defaults should be mirrored in #defaults_str, unless there are
  # none.
  #
  # When defining a new command subclass, use add_option to add command-line
  # switches.
  #
  # Unhandled arguments (gem names, files, etc.) are left in
  # <tt>options[:args]</tt>.

  def initialize(command, summary=nil, defaults={})
    @command = command
    @summary = summary
    @program_name = "gem #{command}"
    @defaults = defaults
    @options = defaults.dup
    @option_groups = Hash.new {|h,k| h[k] = [] }
    @deprecated_options = { command => {} }
    @parser = nil
    @when_invoked = nil
  end

  ##
  # True if +long+ begins with the characters from +short+.

  def begins?(long, short)
    return false if short.nil?
    long[0, short.length] == short
  end

  ##
  # Override to provide command handling.
  #
  # #options will be filled in with your parsed options, unparsed options will
  # be left in <tt>options[:args]</tt>.
  #
  # See also: #get_all_gem_names, #get_one_gem_name,
  # #get_one_optional_argument

  def execute
    raise Gem::Exception, "generic command has no actions"
  end

  ##
  # Display to the user that a gem couldn't be found and reasons why
  #--

  def show_lookup_failure(gem_name, version, errors, suppress_suggestions = false, required_by = nil)
    gem = "'#{gem_name}' (#{version})"
    msg = String.new "Could not find a valid gem #{gem}"

    if errors && !errors.empty?
      msg << ", here is why:\n"
      errors.each {|x| msg << "          #{x.wordy}\n" }
    else
      if required_by && gem != required_by
        msg << " (required by #{required_by}) in any repository"
      else
        msg << " in any repository"
      end
    end

    alert_error msg

    unless suppress_suggestions
      suggestions = Gem::SpecFetcher.fetcher.suggest_gems_from_name(gem_name, :latest, 10)
      unless suggestions.empty?
        alert_error "Possible alternatives: #{suggestions.join(", ")}"
      end
    end
  end

  ##
  # Get all gem names from the command line.

  def get_all_gem_names
    args = options[:args]

    if args.nil? || args.empty?
      raise Gem::CommandLineError,
            "Please specify at least one gem name (e.g. gem build GEMNAME)"
    end

    args.select {|arg| arg !~ /^-/ }
  end

  ##
  # Get all [gem, version] from the command line.
  #
  # An argument in the form gem:ver is pull apart into the gen name and version,
  # respectively.
  def get_all_gem_names_and_versions
    get_all_gem_names.map do |name|
      if /\A(.*):(#{Gem::Requirement::PATTERN_RAW})\z/ =~ name
        [$1, $2]
      else
        [name]
      end
    end
  end

  ##
  # Get a single gem name from the command line.  Fail if there is no gem name
  # or if there is more than one gem name given.

  def get_one_gem_name
    args = options[:args]

    if args.nil? || args.empty?
      raise Gem::CommandLineError,
            "Please specify a gem name on the command line (e.g. gem build GEMNAME)"
    end

    if args.size > 1
      raise Gem::CommandLineError,
            "Too many gem names (#{args.join(', ')}); please specify only one"
    end

    args.first
  end

  ##
  # Get a single optional argument from the command line.  If more than one
  # argument is given, return only the first. Return nil if none are given.

  def get_one_optional_argument
    args = options[:args] || []
    args.first
  end

  ##
  # Override to provide details of the arguments a command takes.  It should
  # return a left-justified string, one argument per line.
  #
  # For example:
  #
  #   def usage
  #     "#{program_name} FILE [FILE ...]"
  #   end
  #
  #   def arguments
  #     "FILE          name of file to find"
  #   end

  def arguments
    ""
  end

  ##
  # Override to display the default values of the command options. (similar to
  # +arguments+, but displays the default values).
  #
  # For example:
  #
  #   def defaults_str
  #     --no-gems-first --no-all
  #   end

  def defaults_str
    ""
  end

  ##
  # Override to display a longer description of what this command does.

  def description
    nil
  end

  ##
  # Override to display the usage for an individual gem command.
  #
  # The text "[options]" is automatically appended to the usage text.

  def usage
    program_name
  end

  ##
  # Display the help message for the command.

  def show_help
    parser.program_name = usage
    say parser
  end

  ##
  # Invoke the command with the given list of arguments.

  def invoke(*args)
    invoke_with_build_args args, nil
  end

  ##
  # Invoke the command with the given list of normal arguments
  # and additional build arguments.

  def invoke_with_build_args(args, build_args)
    handle_options args

    options[:build_args] = build_args

    if options[:silent]
      old_ui = self.ui
      self.ui = ui = Gem::SilentUI.new
    end

    if options[:help]
      show_help
    elsif @when_invoked
      @when_invoked.call options
    else
      execute
    end
  ensure
    if ui
      self.ui = old_ui
      ui.close
    end
  end

  ##
  # Call the given block when invoked.
  #
  # Normal command invocations just executes the +execute+ method of the
  # command.  Specifying an invocation block allows the test methods to
  # override the normal action of a command to determine that it has been
  # invoked correctly.

  def when_invoked(&block)
    @when_invoked = block
  end

  ##
  # Add a command-line option and handler to the command.
  #
  # See Gem::OptionParser#make_switch for an explanation of +opts+.
  #
  # +handler+ will be called with two values, the value of the argument and
  # the options hash.
  #
  # If the first argument of add_option is a Symbol, it's used to group
  # options in output.  See `gem help list` for an example.

  def add_option(*opts, &handler) # :yields: value, options
    group_name = Symbol === opts.first ? opts.shift : :options

    raise "Do not pass an empty string in opts" if opts.include?("")

    @option_groups[group_name] << [opts, handler]
  end

  ##
  # Remove previously defined command-line argument +name+.

  def remove_option(name)
    @option_groups.each do |_, option_list|
      option_list.reject! {|args, _| args.any? {|x| x.is_a?(String) && x =~ /^#{name}/ } }
    end
  end

  ##
  # Mark a command-line option as deprecated, and optionally specify a
  # deprecation horizon.
  #
  # Note that with the current implementation, every version of the option needs
  # to be explicitly deprecated, so to deprecate an option defined as
  #
  #   add_option('-t', '--[no-]test', 'Set test mode') do |value, options|
  #     # ... stuff ...
  #   end
  #
  # you would need to explicitly add a call to `deprecate_option` for every
  # version of the option you want to deprecate, like
  #
  #   deprecate_option('-t')
  #   deprecate_option('--test')
  #   deprecate_option('--no-test')

  def deprecate_option(name, version: nil, extra_msg: nil)
    @deprecated_options[command].merge!({ name => { "rg_version_to_expire" => version, "extra_msg" => extra_msg } })
  end

  def check_deprecated_options(options)
    options.each do |option|
      if option_is_deprecated?(option)
        deprecation = @deprecated_options[command][option]
        version_to_expire = deprecation["rg_version_to_expire"]

        deprecate_option_msg = if version_to_expire
          "The \"#{option}\" option has been deprecated and will be removed in Rubygems #{version_to_expire}."
        else
          "The \"#{option}\" option has been deprecated and will be removed in future versions of Rubygems."
        end

        extra_msg = deprecation["extra_msg"]

        deprecate_option_msg += " #{extra_msg}" if extra_msg

        alert_warning(deprecate_option_msg)
      end
    end
  end

  ##
  # Merge a set of command options with the set of default options (without
  # modifying the default option hash).

  def merge_options(new_options)
    @options = @defaults.clone
    new_options.each {|k,v| @options[k] = v }
  end

  ##
  # True if the command handles the given argument list.

  def handles?(args)
    begin
      parser.parse!(args.dup)
      return true
    rescue
      return false
    end
  end

  ##
  # Handle the given list of arguments by parsing them and recording the
  # results.

  def handle_options(args)
    args = add_extra_args(args)
    check_deprecated_options(args)
    @options = Marshal.load Marshal.dump @defaults # deep copy
    parser.parse!(args)
    @options[:args] = args
  end

  ##
  # Adds extra args from ~/.gemrc

  def add_extra_args(args)
    result = []

    s_extra = Gem::Command.specific_extra_args(@command)
    extra = Gem::Command.extra_args + s_extra

    until extra.empty? do
      ex = []
      ex << extra.shift
      ex << extra.shift if extra.first.to_s =~ /^[^-]/ # rubocop:disable Performance/StartWith
      result << ex if handles?(ex)
    end

    result.flatten!
    result.concat(args)
    result
  end

  def deprecated?
    false
  end

  private

  def option_is_deprecated?(option)
    @deprecated_options[command].has_key?(option)
  end

  def add_parser_description # :nodoc:
    return unless description

    formatted = description.split("\n\n").map do |chunk|
      wrap chunk, 80 - 4
    end.join "\n"

    @parser.separator nil
    @parser.separator "  Description:"
    formatted.split("\n").each do |line|
      @parser.separator "    #{line.rstrip}"
    end
  end

  def add_parser_options # :nodoc:
    @parser.separator nil

    regular_options = @option_groups.delete :options

    configure_options "", regular_options

    @option_groups.sort_by {|n,_| n.to_s }.each do |group_name, option_list|
      @parser.separator nil
      configure_options group_name, option_list
    end
  end

  ##
  # Adds a section with +title+ and +content+ to the parser help view.  Used
  # for adding command arguments and default arguments.

  def add_parser_run_info(title, content)
    return if content.empty?

    @parser.separator nil
    @parser.separator "  #{title}:"
    content.split(/\n/).each do |line|
      @parser.separator "    #{line}"
    end
  end

  def add_parser_summary # :nodoc:
    return unless @summary

    @parser.separator nil
    @parser.separator "  Summary:"
    wrap(@summary, 80 - 4).split("\n").each do |line|
      @parser.separator "    #{line.strip}"
    end
  end

  ##
  # Create on demand parser.

  def parser
    create_option_parser if @parser.nil?
    @parser
  end

  ##
  # Creates an option parser and fills it in with the help info for the
  # command.

  def create_option_parser
    @parser = Gem::OptionParser.new

    add_parser_options

    @parser.separator nil
    configure_options "Common", Gem::Command.common_options

    add_parser_run_info "Arguments", arguments
    add_parser_summary
    add_parser_description
    add_parser_run_info "Defaults", defaults_str
  end

  def configure_options(header, option_list)
    return if option_list.nil? || option_list.empty?

    header = header.to_s.empty? ? "" : "#{header} "
    @parser.separator "  #{header}Options:"

    option_list.each do |args, handler|
      @parser.on(*args) do |value|
        handler.call(value, @options)
      end
    end

    @parser.separator ""
  end

  ##
  # Wraps +text+ to +width+

  def wrap(text, width) # :doc:
    text.gsub(/(.{1,#{width}})( +|$\n?)|(.{1,#{width}})/, "\\1\\3\n")
  end

  # ----------------------------------------------------------------
  # Add the options common to all commands.

  add_common_option("-h", "--help",
                    "Get help on this command") do |value, options|
    options[:help] = true
  end

  add_common_option("-V", "--[no-]verbose",
                    "Set the verbose level of output") do |value, options|
    # Set us to "really verbose" so the progress meter works
    if Gem.configuration.verbose && value
      Gem.configuration.verbose = 1
    else
      Gem.configuration.verbose = value
    end
  end

  add_common_option("-q", "--quiet", "Silence command progress meter") do |value, options|
    Gem.configuration.verbose = false
  end

  add_common_option("--silent",
                    "Silence RubyGems output") do |value, options|
    options[:silent] = true
  end

  # Backtrace and config-file are added so they show up in the help
  # commands.  Both options are actually handled before the other
  # options get parsed.

  add_common_option("--config-file FILE",
                    "Use this config file instead of default") do
  end

  add_common_option("--backtrace",
                    "Show stack backtrace on errors") do
  end

  add_common_option("--debug",
                    "Turn on Ruby debugging") do
  end

  add_common_option("--norc",
                    "Avoid loading any .gemrc file") do
  end

  # :stopdoc:

  HELP = <<-HELP.freeze
RubyGems is a package manager for Ruby.

  Usage:
    gem -h/--help
    gem -v/--version
    gem command [arguments...] [options...]

  Examples:
    gem install rake
    gem list --local
    gem build package.gemspec
    gem push package-0.0.1.gem
    gem help install

  Further help:
    gem help commands            list all 'gem' commands
    gem help examples            show some examples of usage
    gem help gem_dependencies    gem dependencies file guide
    gem help platforms           gem platforms guide
    gem help <COMMAND>           show help on COMMAND
                                   (e.g. 'gem help install')
    gem server                   present a web page at
                                 http://localhost:8808/
                                 with info about installed gems
  Further information:
    https://guides.rubygems.org
  HELP

  # :startdoc:
end

##
# \Commands will be placed in this namespace

module Gem::Commands
end
