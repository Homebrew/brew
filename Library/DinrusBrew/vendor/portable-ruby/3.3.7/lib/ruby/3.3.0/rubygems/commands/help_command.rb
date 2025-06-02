# frozen_string_literal: true

require_relative "../command"

class Gem::Commands::HelpCommand < Gem::Command
  # :stopdoc:
  EXAMPLES = <<-EOF
Some examples of 'gem' usage.

* Install 'rake', either from local directory or remote server:

    gem install rake

* Install 'rake', only from remote server:

    gem install rake --remote

* Install 'rake', but only version 0.3.1, even if dependencies
  are not met, and into a user-specific directory:

    gem install rake --version 0.3.1 --force --user-install

* List local gems whose name begins with 'D':

    gem list D

* List local and remote gems whose name contains 'log':

    gem search log --both

* List only remote gems whose name contains 'log':

    gem search log --remote

* Uninstall 'rake':

    gem uninstall rake

* Create a gem:

    See https://guides.rubygems.org/make-your-own-gem/

* See information about RubyGems:

    gem environment

* Update all gems on your system:

    gem update

* Update your local version of RubyGems

    gem update --system
  EOF

  GEM_DEPENDENCIES = <<-EOF
A gem dependencies file allows installation of a consistent set of gems across
multiple environments.  The RubyGems implementation is designed to be
compatible with Bundler's Gemfile format.  You can see additional
documentation on the format at:

  https://bundler.io

RubyGems automatically looks for these gem dependencies files:

* gem.deps.rb
* Gemfile
* Isolate

These files are looked up automatically using `gem install -g`, or you can
specify a custom file.

When the RUBYGEMS_GEMDEPS environment variable is set to a gem dependencies
file the gems from that file will be activated at startup time.  Set it to a
specific filename or to "-" to have RubyGems automatically discover the gem
dependencies file by walking up from the current directory.

You can also activate gem dependencies at program startup using
Gem.use_gemdeps.

NOTE: Enabling automatic discovery on multiuser systems can lead to execution
of arbitrary code when used from directories outside your control.

Gem Dependencies
================

Use #gem to declare which gems you directly depend upon:

  gem 'rake'

To depend on a specific set of versions:

  gem 'rake', '~> 10.3', '>= 10.3.2'

RubyGems will require the gem name when activating the gem using
the RUBYGEMS_GEMDEPS environment variable or Gem::use_gemdeps.  Use the
require: option to override this behavior if the gem does not have a file of
that name or you don't want to require those files:

  gem 'my_gem', require: 'other_file'

To prevent RubyGems from requiring any files use:

  gem 'my_gem', require: false

To load dependencies from a .gemspec file:

  gemspec

RubyGems looks for the first .gemspec file in the current directory.  To
override this use the name: option:

  gemspec name: 'specific_gem'

To look in a different directory use the path: option:

  gemspec name: 'specific_gem', path: 'gemspecs'

To depend on a gem unpacked into a local directory:

  gem 'modified_gem', path: 'vendor/modified_gem'

To depend on a gem from git:

  gem 'private_gem', git: 'git@my.company.example:private_gem.git'

To depend on a gem from github:

  gem 'private_gem', github: 'my_company/private_gem'

To depend on a gem from a github gist:

  gem 'bang', gist: '1232884'

Git, github and gist support the ref:, branch: and tag: options to specify a
commit reference or hash, branch or tag respectively to use for the gem.

Setting the submodules: option to true for git, github and gist dependencies
causes fetching of submodules when fetching the repository.

You can depend on multiple gems from a single repository with the git method:

  git 'https://github.com/rails/rails.git' do
    gem 'activesupport'
    gem 'activerecord'
  end

Gem Sources
===========

RubyGems uses the default sources for regular `gem install` for gem
dependencies files.  Unlike bundler, you do need to specify a source.

You can override the sources used for downloading gems with:

  source 'https://gem_server.example'

You may specify multiple sources.  Unlike bundler the prepend: option is not
supported. Sources are used in-order, to prepend a source place it at the
front of the list.

Gem Platform
============

You can restrict gem dependencies to specific platforms with the #platform
and #platforms methods:

  platform :ruby_21 do
    gem 'debugger'
  end

See the bundler Gemfile manual page for a list of platforms supported in a gem
dependencies file.:

  https://bundler.io/v2.5/man/gemfile.5.html

Ruby Version and Engine Dependency
==================================

You can specify the version, engine and engine version of ruby to use with
your gem dependencies file.  If you are not running the specified version
RubyGems will raise an exception.

To depend on a specific version of ruby:

  ruby '2.1.2'

To depend on a specific ruby engine:

  ruby '1.9.3', engine: 'jruby'

To depend on a specific ruby engine version:

  ruby '1.9.3', engine: 'jruby', engine_version: '1.7.11'

Grouping Dependencies
=====================

Gem dependencies may be placed in groups that can be excluded from install.
Dependencies required for development or testing of your code may be excluded
when installed in a production environment.

A #gem dependency may be placed in a group using the group: option:

  gem 'minitest', group: :test

To install dependencies from a gemfile without specific groups use the
`--without` option for `gem install -g`:

  $ gem install -g --without test

The group: option also accepts multiple groups if the gem fits in multiple
categories.

Multiple groups may be excluded during install by comma-separating the groups for `--without` or by specifying `--without` multiple times.

The #group method can also be used to place gems in groups:

  group :test do
    gem 'minitest'
    gem 'minitest-emoji'
  end

The #group method allows multiple groups.

The #gemspec development dependencies are placed in the :development group by
default.  This may be overridden with the :development_group option:

  gemspec development_group: :other

  EOF

  PLATFORMS = <<-'EOF'
RubyGems platforms are composed of three parts, a CPU, an OS, and a
version.  These values are taken from values in rbconfig.rb.  You can view
your current platform by running `gem environment`.

RubyGems matches platforms as follows:

  * The CPU must match exactly unless one of the platforms has
    "universal" as the CPU or the local CPU starts with "arm" and the gem's
    CPU is exactly "arm" (for gems that support generic ARM architecture).
  * The OS must match exactly.
  * The versions must match exactly unless one of the versions is nil.

For commands that install, uninstall and list gems, you can override what
RubyGems thinks your platform is with the --platform option.  The platform
you pass must match "#{cpu}-#{os}" or "#{cpu}-#{os}-#{version}".  On mswin
platforms, the version is the compiler version, not the OS version.  (Ruby
compiled with VC6 uses "60" as the compiler version, VC8 uses "80".)

For the ARM architecture, gems with a platform of "arm-linux" should run on a
reasonable set of ARM CPUs and not depend on instructions present on a limited
subset of the architecture.  For example, the binary should run on platforms
armv5, armv6hf, armv6l, armv7, etc.  If you use the "arm-linux" platform
please test your gem on a variety of ARM hardware before release to ensure it
functions correctly.

Example platforms:

  x86-freebsd        # Any FreeBSD version on an x86 CPU
  universal-darwin-8 # Darwin 8 only gems that run on any CPU
  x86-mswin32-80     # Windows gems compiled with VC8
  armv7-linux        # Gem complied for an ARMv7 CPU running linux
  arm-linux          # Gem compiled for any ARM CPU running linux

When building platform gems, set the platform in the gem specification to
Gem::Platform::CURRENT.  This will correctly mark the gem with your ruby's
platform.
  EOF

  # NOTE: when updating also update Gem::Command::HELP

  SUBCOMMANDS = [
    ["commands",         :show_commands],
    ["options",          Gem::Command::HELP],
    ["examples",         EXAMPLES],
    ["gem_dependencies", GEM_DEPENDENCIES],
    ["platforms",        PLATFORMS],
  ].freeze
  # :startdoc:

  def initialize
    super "help", "Provide help on the 'gem' command"

    @command_manager = Gem::CommandManager.instance
  end

  def usage # :nodoc:
    "#{program_name} ARGUMENT"
  end

  def execute
    arg = options[:args][0]

    _, help = SUBCOMMANDS.find do |command,|
      begins? command, arg
    end

    if help
      if Symbol === help
        send help
      else
        say help
      end
      return
    end

    if options[:help]
      show_help

    elsif arg
      show_command_help arg

    else
      say Gem::Command::HELP
    end
  end

  def show_commands # :nodoc:
    out = []
    out << "GEM commands are:"
    out << nil

    margin_width = 4

    desc_width = @command_manager.command_names.map(&:size).max + 4

    summary_width = 80 - margin_width - desc_width
    wrap_indent = " " * (margin_width + desc_width)
    format = "#{" " * margin_width}%-#{desc_width}s%s"

    @command_manager.command_names.each do |cmd_name|
      command = @command_manager[cmd_name]

      next if command&.deprecated?

      summary =
        if command
          command.summary
        else
          "[No command found for #{cmd_name}]"
        end

      summary = wrap(summary, summary_width).split "\n"
      out << format(format, cmd_name, summary.shift)
      until summary.empty? do
        out << "#{wrap_indent}#{summary.shift}"
      end
    end

    out << nil
    out << "For help on a particular command, use 'gem help COMMAND'."
    out << nil
    out << "Commands may be abbreviated, so long as they are unambiguous."
    out << "e.g. 'gem i rake' is short for 'gem install rake'."

    say out.join("\n")
  end

  def show_command_help(command_name) # :nodoc:
    command_name = command_name.downcase

    possibilities = @command_manager.find_command_possibilities command_name

    if possibilities.size == 1
      command = @command_manager[possibilities.first]
      command.invoke("--help")
    elsif possibilities.size > 1
      alert_warning "Ambiguous command #{command_name} (#{possibilities.join(", ")})"
    else
      alert_warning "Unknown command #{command_name}. Try: gem help commands"
    end
  end
end
