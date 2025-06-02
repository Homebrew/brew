# frozen_string_literal: true

require_relative "../command"
require_relative "../dependency_installer"
require_relative "../gem_runner"
require_relative "../package"
require_relative "../version_option"

class Gem::Commands::ExecCommand < Gem::Command
  include Gem::VersionOption

  def initialize
    super "exec", "Run a command from a gem", {
      version: Gem::Requirement.default,
    }

    add_version_option
    add_prerelease_option "to be installed"

    add_option "-g", "--gem GEM", "run the executable from the given gem" do |value, options|
      options[:gem_name] = value
    end

    add_option(:"Install/Update", "--conservative",
      "Prefer the most recent installed version, ",
      "rather than the latest version overall") do |_value, options|
      options[:conservative] = true
    end
  end

  def arguments # :nodoc:
    "COMMAND  the executable command to run"
  end

  def defaults_str # :nodoc:
    "--version '#{Gem::Requirement.default}'"
  end

  def description # :nodoc:
    <<-EOF
The exec command handles installing (if necessary) and running an executable
from a gem, regardless of whether that gem is currently installed.

The exec command can be thought of as a shortcut to running `gem install` and
then the executable from the installed gem.

For example, `gem exec rails new .` will run `rails new .` in the current
directory, without having to manually run `gem install rails`.
Additionally, the exec command ensures the most recent version of the gem
is used (unless run with `--conservative`), and that the gem is not installed
to the same gem path as user-installed gems.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} [options --] COMMAND [args]"
  end

  def execute
    check_executable

    print_command
    if options[:gem_name] == "gem" && options[:executable] == "gem"
      set_gem_exec_install_paths
      Gem::GemRunner.new.run options[:args]
      return
    elsif options[:conservative]
      install_if_needed
    else
      install
      activate!
    end

    load!
  end

  private

  def handle_options(args)
    args = add_extra_args(args)
    check_deprecated_options(args)
    @options = Marshal.load Marshal.dump @defaults # deep copy
    parser.order!(args) do |v|
      # put the non-option back at the front of the list of arguments
      args.unshift(v)

      # stop parsing once we hit the first non-option,
      # so you can call `gem exec rails --version` and it prints the rails
      # version rather than rubygem's
      break
    end
    @options[:args] = args

    options[:executable], gem_version = extract_gem_name_and_version(options[:args].shift)
    options[:gem_name] ||= options[:executable]

    if gem_version
      if options[:version].none?
        options[:version] = Gem::Requirement.new(gem_version)
      else
        options[:version].concat [gem_version]
      end
    end

    if options[:prerelease] && !options[:version].prerelease?
      if options[:version].none?
        options[:version] = Gem::Requirement.default_prerelease
      else
        options[:version].concat [Gem::Requirement.default_prerelease]
      end
    end
  end

  def check_executable
    if options[:executable].nil?
      raise Gem::CommandLineError,
        "Please specify an executable to run (e.g. #{program_name} COMMAND)"
    end
  end

  def print_command
    verbose "running #{program_name} with:\n"
    opts = options.reject {|_, v| v.nil? || Array(v).empty? }
    max_length = opts.map {|k, _| k.size }.max
    opts.each do |k, v|
      next if v.nil?
      verbose "\t#{k.to_s.rjust(max_length)}: #{v}"
    end
    verbose ""
  end

  def install_if_needed
    activate!
  rescue Gem::MissingSpecError
    verbose "#{Gem::Dependency.new(options[:gem_name], options[:version])} not available locally, installing from remote"
    install
    activate!
  end

  def set_gem_exec_install_paths
    home = Gem.dir

    ENV["GEM_PATH"] = ([home] + Gem.path).join(File::PATH_SEPARATOR)
    ENV["GEM_HOME"] = home
    Gem.clear_paths
  end

  def install
    set_gem_exec_install_paths

    gem_name = options[:gem_name]
    gem_version = options[:version]

    install_options = options.merge(
      minimal_deps: false,
      wrappers: true
    )

    suppress_always_install do
      dep_installer = Gem::DependencyInstaller.new install_options

      request_set = dep_installer.resolve_dependencies gem_name, gem_version

      verbose "Gems to install:"
      request_set.sorted_requests.each do |activation_request|
        verbose "\t#{activation_request.full_name}"
      end

      request_set.install install_options
    end

    Gem::Specification.reset
  rescue Gem::InstallError => e
    alert_error "Error installing #{gem_name}:\n\t#{e.message}"
    terminate_interaction 1
  rescue Gem::GemNotFoundException => e
    show_lookup_failure e.name, e.version, e.errors, false

    terminate_interaction 2
  rescue Gem::UnsatisfiableDependencyError => e
    show_lookup_failure e.name, e.version, e.errors, false,
                        "'#{gem_name}' (#{gem_version})"

    terminate_interaction 2
  end

  def activate!
    gem(options[:gem_name], options[:version])
    Gem.finish_resolve

    verbose "activated #{options[:gem_name]} (#{Gem.loaded_specs[options[:gem_name]].version})"
  end

  def load!
    argv = ARGV.clone
    ARGV.replace options[:args]

    exe = executable = options[:executable]

    contains_executable = Gem.loaded_specs.values.select do |spec|
      spec.executables.include?(executable)
    end

    if contains_executable.any? {|s| s.name == executable }
      contains_executable.select! {|s| s.name == executable }
    end

    if contains_executable.empty?
      if (spec = Gem.loaded_specs[executable]) && (exe = spec.executable)
        contains_executable << spec
      else
        alert_error "Failed to load executable `#{executable}`," \
              " are you sure the gem `#{options[:gem_name]}` contains it?"
        terminate_interaction 1
      end
    end

    if contains_executable.size > 1
      alert_error "Ambiguous which gem `#{executable}` should come from: " \
            "the options are #{contains_executable.map(&:name)}, " \
            "specify one via `-g`"
      terminate_interaction 1
    end

    load Gem.activate_bin_path(contains_executable.first.name, exe, ">= 0.a")
  ensure
    ARGV.replace argv
  end

  def suppress_always_install
    name = :always_install
    cls = ::Gem::Resolver::InstallerSet
    method = cls.instance_method(name)
    cls.remove_method(name)
    cls.define_method(name) { [] }

    begin
      yield
    ensure
      cls.remove_method(name)
      cls.define_method(name, method)
    end
  end
end
