# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "fileutils"

module Homebrew
  module DevCmd
    class Prof < AbstractCommand
      cmd_args do
        description <<~EOS
          Run Homebrew with a Ruby profiler. For example, `brew prof readall`.
        EOS
        switch "--stackprof",
               description: "Use `stackprof` instead of `ruby-prof` (the default)."
        switch "--vernier",
               description: "Use `vernier` instead of `ruby-prof` (the default)."

        named_args :command, min: 1
      end

      sig { override.void }
      def run
        Homebrew.install_bundler_gems!(groups: ["prof"], setup_path: false)

        brew_rb = (HOMEBREW_LIBRARY_PATH/"brew.rb").resolved_path
        FileUtils.mkdir_p "prof"
        cmd = T.must(args.named.first)

        case Commands.path(cmd)&.extname
        when ".rb"
          # expected file extension so we do nothing
        when ".sh"
          raise UsageError, <<~EOS
            `#{cmd}` is a Bash command!
            Try `hyperfine` for benchmarking instead.
          EOS
        else
          raise UsageError, "`#{cmd}` is an unknown command!"
        end

        Homebrew.setup_gem_environment!

        if args.stackprof?
          with_env HOMEBREW_STACKPROF: "1" do
            system(*HOMEBREW_RUBY_EXEC_ARGS, brew_rb, *args.named)
          end
          output_filename = "prof/d3-flamegraph.html"
          safe_system "stackprof --d3-flamegraph prof/stackprof.dump > #{output_filename}"
          exec_browser output_filename
        elsif args.vernier?
          output_filename = "prof/vernier.json"
          Process::UID.change_privilege(Process.euid) if Process.euid != Process.uid
          safe_system "vernier", "run", "--output=#{output_filename}", "--allocation_interval=500", "--",
                      RUBY_PATH, brew_rb, *args.named
          ohai "Profiling complete!"
          puts "Upload the results from #{output_filename} to:"
          puts "  #{Formatter.url("https://vernier.prof")}"
        else
          output_filename = "prof/call_stack.html"
          safe_system "ruby-prof", "--printer=call_stack", "--file=#{output_filename}", brew_rb, "--", *args.named
          exec_browser output_filename
        end
      rescue OptionParser::InvalidOption => e
        ofail e

        # The invalid option could have been meant for the subcommand.
        # Suggest `brew prof list -r` -> `brew prof -- list -r`
        args = ARGV - ["--"]
        puts "Try `brew prof -- #{args.join(" ")}` instead."
      end
    end
  end
end
