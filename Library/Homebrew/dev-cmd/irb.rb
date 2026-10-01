# typed: strict
# frozen_string_literal: true

require "abstract_command"

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
               description: "Use Pry instead of IRB.",
               env:         :pry,
               replacement: "the default IRB backend (Pry is largely unmaintained upstream)",
               odisabled:   true
      end

      # work around IRB modifying ARGV.
      sig { params(argv: T.nilable(T::Array[String])).void }
      def initialize(argv = nil) = super(argv || ARGV.dup.freeze)

      sig { override.void }
      def run
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

        require "keg"
        require "cask"

        ohai "Interactive Homebrew Shell", "Example commands available with: `brew irb --examples`"
        ENV["IRBRC"] = (HOMEBREW_LIBRARY_PATH/"brew_irbrc").to_s

        $stdout.flush
        $stderr.flush
        exec File.join(RbConfig::CONFIG["bindir"], "irb"), "-I", $LOAD_PATH.join(File::PATH_SEPARATOR), *args.named
      end
    end
  end
end
