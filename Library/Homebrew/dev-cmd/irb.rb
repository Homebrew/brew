# typed: true
# frozen_string_literal: true

require "formulary"
require "cask/cask_loader"
require "cli/parser"

class String
  def f(*args)
    require "formula"
    Formulary.factory(self, *args)
  end

  def c(config: nil)
    Cask::CaskLoader.load(self, config: config)
  end
end

class Symbol
  def f(*args)
    to_s.f(*args)
  end

  def c(config: nil)
    to_s.c(config: config)
  end
end

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def irb_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Enter the interactive Homebrew Ruby shell.
      EOS
      switch "--examples",
             description: "Show several examples."
      switch "--pry",
             env:         :pry,
             description: "Use Pry instead of IRB. Implied if `HOMEBREW_PRY` is set."
    end
  end

  def irb
    # work around IRB modifying ARGV.
    args = irb_args.parse(ARGV.dup.freeze)

    clean_argv

    if args.examples?
      puts <<~EOS
        'v8'.f # => instance of the v8 formula
        :hub.f.latest_version_installed?
        :lua.f.methods - 1.methods
        :mpd.f.recursive_dependencies.reject(&:installed?)

        'vlc'.c # => instance of the vlc cask
        :tsh.c.livecheckable?
      EOS
      return
    end

    if args.pry?
      Homebrew.install_bundler_gems!(groups: ["pry"])
      require "pry"
    else
      require "irb"
    end

    require "formula"
    require "keg"
    require "cask"

    ohai "Interactive Homebrew Shell", "Example commands available with: `brew irb --examples`"
    if args.pry?
      Pry.config.should_load_rc = false # skip loading .pryrc
      Pry.config.history_file = "#{Dir.home}/.brew_pry_history"
      Pry.config.memory_size = 100 # max lines to save to history file
      Pry.config.prompt_name = "brew"

      Pry.start
    else
      ENV["IRBRC"] = (HOMEBREW_LIBRARY_PATH/"brew_irbrc").to_s

      IRB.start
    end
  end

  # Remove the `--debug`, `--verbose` and `--quiet` options which cause problems
  # for IRB and have already been parsed by the CLI::Parser.
  def clean_argv
    global_options = Homebrew::CLI::Parser
                     .global_options
                     .flat_map { |options| options[0..1] }
    ARGV.reject! { |arg| global_options.include?(arg) }
  end
end
