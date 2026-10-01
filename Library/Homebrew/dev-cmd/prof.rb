# typed: strict
# frozen_string_literal: true

require "system_command"
require "utils/browser"

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
        switch "--timings",
               description: "Record machine-readable timings for Homebrew command phases."
        conflicts "--timings", "--stackprof"
        conflicts "--timings", "--vernier"

        named_args :command, min: 1
      end

      sig { override.void }
      def run
        Utils::GemSetup.install_bundler_gems!(groups: ["prof"], setup_path: false) unless args.timings?

        brew_rb = Utils::Path.resolved_path(HOMEBREW_LIBRARY_PATH/"brew.rb")
        FileUtils.mkdir_p "prof"
        cmd = args.named.fetch(0)

        case Commands.path(cmd)&.extname
        when ".rb"
          # expected file extension so we do nothing
        when ".sh"
          raise UsageError, <<~EOS
            `#{cmd}` is a Bash command!
            Try `brew benchmark --exec` for benchmarking instead.
          EOS
        else
          raise UsageError, "`#{cmd}` is an unknown command!"
        end

        if args.timings?
          output_filename = "prof/timings.json"
          SystemCommand.safe_system(*HOMEBREW_RUBY_EXEC_ARGS, brew_rb, *args.named,
                                    env: { "HOMEBREW_PHASE_TIMINGS" => output_filename })
          ohai "Phase timings written to #{output_filename}"
          return
        end

        Utils::GemSetup.setup_gem_environment!

        if args.stackprof?
          with_env HOMEBREW_STACKPROF: "1" do
            system(*HOMEBREW_RUBY_EXEC_ARGS, brew_rb, *args.named)
          end
          output_filename = "prof/d3-flamegraph.html"
          SystemCommand.safe_system "/bin/sh", "-c",
                                    "stackprof --d3-flamegraph prof/stackprof.dump > #{output_filename}"
          # `brew prof` is often run from tests or scripts. Only open the HTML
          # report automatically when the user is attached to a terminal.
          Utils::Browser.open output_filename if $stdout.tty?
        elsif args.vernier?
          output_filename = "prof/vernier.json"
          # Avoid `vernier run`: it injects `vernier/autorun` through `RUBYOPT`,
          # which child Ruby processes inherit. Profiling only this Ruby process
          # keeps nested `brew` commands from trying to write the same profile.
          #
          # `HOMEBREW_SPAWN_SYSTEM` is intentionally scoped to this profiled
          # process. It lets selected process helpers avoid manual fork paths
          # that can inherit Vernier's active native collector state.
          SystemCommand.safe_system(
            RUBY_PATH, "-I", (Pathname(Gem::Specification.find_by_name("vernier").full_gem_path)/"lib").to_s,
            "-r", "vernier/autorun",
            "-r", (HOMEBREW_LIBRARY_PATH/"prof/vernier_fork_guard").to_s, brew_rb, *args.named,
            env: {
              "HOMEBREW_SPAWN_SYSTEM"       => "1",
              "VERNIER_ALLOCATION_INTERVAL" => "500",
              "VERNIER_OUTPUT"              => output_filename,
            }
          )
          ohai "Profiling complete!"
          puts "Upload the results from #{output_filename} to:"
          puts "  #{Formatter.url("https://vernier.prof")}"
        else
          output_filename = "prof/call_stack.html"
          SystemCommand.safe_system "ruby-prof", "--printer=call_stack", "--file=#{output_filename}", brew_rb, "--",
                                    *args.named
          # Match the stackprof behaviour above: generating the file is useful
          # in non-interactive runs but launching a browser is not.
          Utils::Browser.open output_filename if $stdout.tty?
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
