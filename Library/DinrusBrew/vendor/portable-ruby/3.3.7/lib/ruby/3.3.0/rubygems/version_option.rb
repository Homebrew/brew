# frozen_string_literal: true

#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require_relative "../rubygems"

##
# Mixin methods for --version and --platform Gem::Command options.

module Gem::VersionOption
  ##
  # Add the --platform option to the option parser.

  def add_platform_option(task = command, *wrap)
    Gem::OptionParser.accept Gem::Platform do |value|
      if value == Gem::Platform::RUBY
        value
      else
        Gem::Platform.new value
      end
    end

    add_option("--platform PLATFORM", Gem::Platform,
               "Specify the platform of gem to #{task}", *wrap) do |value, options|
      unless options[:added_platform]
        Gem.platforms = [Gem::Platform::RUBY]
        options[:added_platform] = true
      end

      Gem.platforms << value unless Gem.platforms.include? value
    end
  end

  ##
  # Add the --prerelease option to the option parser.

  def add_prerelease_option(*wrap)
    add_option("--[no-]prerelease",
               "Allow prerelease versions of a gem", *wrap) do |value, options|
      options[:prerelease] = value
      options[:explicit_prerelease] = true
    end
  end

  ##
  # Add the --version option to the option parser.

  def add_version_option(task = command, *wrap)
    Gem::OptionParser.accept Gem::Requirement do |value|
      Gem::Requirement.new(*value.split(/\s*,\s*/))
    end

    add_option("-v", "--version VERSION", Gem::Requirement,
               "Specify version of gem to #{task}", *wrap) do |value, options|
      # Allow handling for multiple --version operators
      if options[:version] && !options[:version].none?
        options[:version].concat([value])
      else
        options[:version] = value
      end

      explicit_prerelease_set = !options[:explicit_prerelease].nil?
      options[:explicit_prerelease] = false unless explicit_prerelease_set

      options[:prerelease] = value.prerelease? unless
        options[:explicit_prerelease]
    end
  end

  ##
  # Extract platform given on the command line

  def get_platform_from_requirements(requirements)
    Gem.platforms[1].to_s if requirements.key? :added_platform
  end
end
