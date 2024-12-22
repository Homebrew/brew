# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "formulary"
require "cask/cask_loader"

class String
  # @!visibility private
  sig { params(args: Integer).returns(Formula) }
  def f(*args)
    Formulary.factory(self, *args)
  end

  # @!visibility private
  sig { params(config: T.nilable(T::Hash[Symbol, T.untyped])).returns(Cask::Cask) }
  def c(config: nil)
    Cask::CaskLoader.load(self, config:)
  end
end

class Symbol
  # @!visibility private
  sig { params(args: Integer).returns(Formula) }
  def f(*args)
    to_s.f(*args)
  end

  # @!visibility private
  sig { params(config: T.nilable(T::Hash[Symbol, T.untyped])).returns(Cask::Cask) }
  def c(config: nil)
    to_s.c(config:)
  end
end

module Homebrew
  module DevCmd
    class Irb < AbstractCommand
      cmd_args do
        description <<~EOS
          Enter the interactive Homebrew Ruby shell.
        EOS
        switch "--examples",
               description: "Show several examples."
        switch "--pry",
               env:         :pry,
               description: "Use Pry instead of IRB. Implied if `HOMEBREW_PRY` is set."
      end

      # work around IRB modifying ARGV.
      sig { params(argv: T.nilable(T::Array[String])).void }
      def initialize(argv = nil) = super(argv || ARGV.dup.freeze)

      sig { override.void }
      def run
        clean_argv

        if args.examples?
          puts <<~EOS
            'v8'.f # => instance of the v8 formula
            :hub.f.latest_version_installed?
            :lua.f.methods - 1.methods
            :mpd.f.recursive_dependencies.reject(&:installed?)

            'vlc'.c # => instance of the vlc cask
            :tsh.c.livecheck_defined?
          EOS
          return
        end

        if args.pry?
          Homebrew.install_bundler_gems!(groups: ["pry"])
          require "pry"
        else
          require "irb"
        end

        require "keg"
        require "cask"

        ohai "Interactive Homebrew Shell", "Example commands available with: `brew irb --examples`"
        if args.pry?
          Pry.config.should_load_rc = false # skip loading .pryrc
          Pry.config.history_file = "#{Dir.home}/.brew_pry_history"
          Pry.config.prompt_name = "brew"

          Pry.start
        else
          ENV["IRBRC"] = (HOMEBREW_LIBRARY_PATH/"brew_irbrc").to_s

          IRB.start
        end
      end

      private

      # Remove the `--debug`, `--verbose` and `--quiet` options which cause problems
      # for IRB and have already been parsed by the CLI::Parser.
      sig { returns(T.nilable(T::Array[Symbol])) }
      def clean_argv
        global_options = Homebrew::CLI::Parser
                         .global_options
                         .flat_map { |options| options[0..1] }
        ARGV.reject! { |arg| global_options.include?(arg) }
      end
    end
  end
end
