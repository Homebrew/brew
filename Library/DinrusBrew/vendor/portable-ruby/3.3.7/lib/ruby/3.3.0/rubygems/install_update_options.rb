# frozen_string_literal: true

#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require_relative "../rubygems"
require_relative "security_option"

##
# Mixin methods for install and update options for Gem::Commands

module Gem::InstallUpdateOptions
  include Gem::SecurityOption

  ##
  # Add the install/update options to the option parser.

  def add_install_update_options
    add_option(:"Install/Update", "-i", "--install-dir DIR",
               "Gem repository directory to get installed",
               "gems") do |value, options|
      options[:install_dir] = File.expand_path(value)
    end

    add_option(:"Install/Update", "-n", "--bindir DIR",
               "Directory where executables will be",
               "placed when the gem is installed") do |value, options|
      options[:bin_dir] = File.expand_path(value)
    end

    add_option(:"Install/Update", "--document [TYPES]", Array,
               "Generate documentation for installed gems",
               "List the documentation types you wish to",
               "generate.  For example: rdoc,ri") do |value, options|
      options[:document] = case value
                           when nil   then %w[ri]
                           when false then []
                           else value
      end
    end

    add_option(:"Install/Update", "--build-root DIR",
               "Temporary installation root. Useful for building",
               "packages. Do not use this when installing remote gems.") do |value, options|
      options[:build_root] = File.expand_path(value)
    end

    add_option(:"Install/Update", "--vendor",
               "Install gem into the vendor directory.",
               "Only for use by gem repackagers.") do |_value, options|
      unless Gem.vendor_dir
        raise Gem::OptionParser::InvalidOption.new "your platform is not supported"
      end

      options[:vendor] = true
      options[:install_dir] = Gem.vendor_dir
    end

    add_option(:"Install/Update", "-N", "--no-document",
               "Disable documentation generation") do |_value, options|
      options[:document] = []
    end

    add_option(:"Install/Update", "-E", "--[no-]env-shebang",
               "Rewrite the shebang line on installed",
               "scripts to use /usr/bin/env") do |value, options|
      options[:env_shebang] = value
    end

    add_option(:"Install/Update", "-f", "--[no-]force",
               "Force gem to install, bypassing dependency",
               "checks") do |value, options|
      options[:force] = value
    end

    add_option(:"Install/Update", "-w", "--[no-]wrappers",
               "Use bin wrappers for executables",
               "Not available on dosish platforms") do |value, options|
      options[:wrappers] = value
    end

    add_security_option

    add_option(:"Install/Update", "--ignore-dependencies",
               "Do not install any required dependent gems") do |value, options|
      options[:ignore_dependencies] = value
    end

    add_option(:"Install/Update", "--[no-]format-executable",
               "Make installed executable names match Ruby.",
               "If Ruby is ruby18, foo_exec will be",
               "foo_exec18") do |value, options|
      options[:format_executable] = value
    end

    add_option(:"Install/Update", "--[no-]user-install",
               "Install in user's home directory instead",
               "of GEM_HOME.") do |value, options|
      options[:user_install] = value
    end

    add_option(:"Install/Update", "--development",
                "Install additional development",
                "dependencies") do |_value, options|
      options[:development] = true
      options[:dev_shallow] = true
    end

    add_option(:"Install/Update", "--development-all",
                "Install development dependencies for all",
                "gems (including dev deps themselves)") do |_value, options|
      options[:development] = true
      options[:dev_shallow] = false
    end

    add_option(:"Install/Update", "--conservative",
                "Don't attempt to upgrade gems already",
                "meeting version requirement") do |_value, options|
      options[:conservative] = true
      options[:minimal_deps] = true
    end

    add_option(:"Install/Update", "--[no-]minimal-deps",
                "Don't upgrade any dependencies that already",
                "meet version requirements") do |value, options|
      options[:minimal_deps] = value
    end

    add_option(:"Install/Update", "--[no-]post-install-message",
                "Print post install message") do |value, options|
      options[:post_install_message] = value
    end

    add_option(:"Install/Update", "-g", "--file [FILE]",
               "Read from a gem dependencies API file and",
               "install the listed gems") do |v,_o|
      v ||= Gem::GEM_DEP_FILES.find do |file|
        File.exist? file
      end

      unless v
        message = v ? v : "(tried #{Gem::GEM_DEP_FILES.join ", "})"

        raise Gem::OptionParser::InvalidArgument,
                "cannot find gem dependencies file #{message}"
      end

      options[:gemdeps] = v
    end

    add_option(:"Install/Update", "--without GROUPS", Array,
               "Omit the named groups (comma separated)",
               "when installing from a gem dependencies",
               "file") do |v,_o|
      options[:without_groups].concat v.map(&:intern)
    end

    add_option(:"Install/Update", "--default",
               "Add the gem's full specification to",
               "specifications/default and extract only its bin") do |v,_o|
      options[:install_as_default] = v
    end

    add_option(:"Install/Update", "--explain",
               "Rather than install the gems, indicate which would",
               "be installed") do |v,_o|
      options[:explain] = v
    end

    add_option(:"Install/Update", "--[no-]lock",
               "Create a lock file (when used with -g/--file)") do |v,_o|
      options[:lock] = v
    end

    add_option(:"Install/Update", "--[no-]suggestions",
               "Suggest alternates when gems are not found") do |v,_o|
      options[:suggest_alternate] = v
    end
  end

  ##
  # Default options for the gem install and update commands.

  def install_update_options
    {
      document: %w[ri],
    }
  end

  ##
  # Default description for the gem install and update commands.

  def install_update_defaults_str
    "--document=ri"
  end
end
