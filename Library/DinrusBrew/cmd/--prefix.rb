# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "fileutils"

module DinrusBrew
  module Cmd
    class Prefix < AbstractCommand
      include FileUtils

      UNBREWED_EXCLUDE_FILES = %w[.DS_Store].freeze
      UNBREWED_EXCLUDE_PATHS = %w[
        */.keepme
        .github/*
        bin/brew
        completions/zsh/_brew
        docs/*
        lib/gdk-pixbuf-2.0/*
        lib/gio/*
        lib/node_modules/*
        lib/python[23].[0-9]/*
        lib/python3.[0-9][0-9]/*
        lib/pypy/*
        lib/pypy3/*
        lib/ruby/gems/[12].*
        lib/ruby/site_ruby/[12].*
        lib/ruby/vendor_ruby/[12].*
        manpages/brew.1
        share/pypy/*
        share/pypy3/*
        share/info/dir
        share/man/whatis
        share/mime/*
        texlive/*
      ].freeze

      sig { override.returns(String) }
      def self.command_name = "--prefix"

      cmd_args do
        description <<~EOS
          Display DinrusBrew's install path. *Default:*

            - macOS ARM: `#{DINRUSBREW_MACOS_ARM_DEFAULT_PREFIX}`
            - macOS Intel: `#{DINRUSBREW_DEFAULT_PREFIX}`
            - Linux: `#{DINRUSBREW_LINUX_DEFAULT_PREFIX}`

          If <formula> is provided, display the location where <formula> is or would be installed.
        EOS
        switch "--unbrewed",
               description: "List files in DinrusBrew's prefix not installed by DinrusBrew."
        switch "--installed",
               description: "Outputs nothing and returns a failing status code if <formula> is not installed."
        conflicts "--unbrewed", "--installed"

        named_args :formula
      end

      sig { override.void }
      def run
        raise UsageError, "`--installed` requires a formula argument." if args.installed? && args.no_named?

        if args.unbrewed?
          raise UsageError, "`--unbrewed` does not take a formula argument." unless args.no_named?

          list_unbrewed
        elsif args.no_named?
          puts DINRUSBREW_PREFIX
        else
          formulae = args.named.to_resolved_formulae
          prefixes = formulae.filter_map do |f|
            next nil if args.installed? && !f.opt_prefix.exist?

            # this case will be short-circuited by brew.sh logic for a single formula
            f.opt_prefix
          end
          puts prefixes
          if args.installed?
            missing_formulae = formulae.reject(&:optlinked?)
                                       .map(&:name)
            return if missing_formulae.blank?

            raise NotAKegError, <<~EOS
              The following formulae are not installed:
              #{missing_formulae.join(" ")}
            EOS
          end
        end
      end

      private

      sig { void }
      def list_unbrewed
        dirs  = DINRUSBREW_PREFIX.subdirs.map { |dir| dir.basename.to_s }
        dirs -= %w[Library Cellar Caskroom .git]

        # Exclude cache, logs and repository, if they are located under the prefix.
        [DINRUSBREW_CACHE, DINRUSBREW_LOGS, DINRUSBREW_REPOSITORY].each do |dir|
          dirs.delete dir.relative_path_from(DINRUSBREW_PREFIX).to_s
        end
        dirs.delete "etc"
        dirs.delete "var"

        arguments = dirs.sort + %w[-type f (]
        arguments.concat UNBREWED_EXCLUDE_FILES.flat_map { |f| %W[! -name #{f}] }
        arguments.concat UNBREWED_EXCLUDE_PATHS.flat_map { |d| %W[! -path #{d}] }
        arguments.push ")"

        cd(DINRUSBREW_PREFIX) { safe_system("find", *arguments) }
      end
    end
  end
end
