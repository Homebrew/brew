# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "system_command"
require "utils/github/actions"

module Homebrew
  module TestBot
    # Wraps command invocations. Instantiated by Test#test.
    # Handles logging and pretty-printing.
    class Step
      include SystemCommand::Mixin

      attr_reader :command, :name, :status, :output, :start_time, :end_time

      # Instantiates a Step object.
      # @param command [Array<String>] Command to execute and arguments.
      # @param env [Hash] Environment variables to set when running command.
      def initialize(command, env:, verbose:, named_args: nil, ignore_failures: false, repository: nil)
        @named_args = [named_args].flatten.compact.map(&:to_s)
        @command = command + @named_args
        @env = env
        @verbose = verbose
        @ignore_failures = ignore_failures
        @repository = repository

        @name = command[1]&.delete("-")
        @status = :running
        @output = nil
      end

      def command_trimmed
        command.reject { |arg| arg.to_s.start_with?("--exclude") }
               .join(" ")
               .delete_prefix("#{HOMEBREW_LIBRARY}/Taps/")
               .delete_prefix("#{HOMEBREW_PREFIX}/")
               .delete_prefix("/usr/bin/")
      end

      def command_short
        (@command - %W[
          brew
          -C
          #{HOMEBREW_PREFIX}
          #{HOMEBREW_REPOSITORY}
          #{@repository}
          #{Dir.pwd}
          --force
          --retry
          --verbose
          --json
        ].freeze).join(" ")
          .gsub(HOMEBREW_PREFIX.to_s, "")
          .gsub(HOMEBREW_REPOSITORY.to_s, "")
          .gsub(@repository.to_s, "")
          .gsub(Dir.pwd, "")
      end

      def passed?
        @status == :passed
      end

      def failed?
        @status == :failed
      end

      def ignored?
        @status == :ignored
      end

      def puts_command
        puts Formatter.headline(command_trimmed, color: :blue)
      end

      def puts_result
        puts Formatter.headline(Formatter.error("FAILED"), color: :red) unless passed?
      end

      def puts_github_actions_annotation(message, title, file, line)
        return unless GitHub::Actions.env_set?

        type = if passed?
          :notice
        elsif ignored?
          :warning
        else
          :error
        end

        annotation = GitHub::Actions::Annotation.new(type, message, title:, file:, line:)
        puts annotation
      end

      def puts_in_github_actions_group(title)
        puts "::group::#{title}" if GitHub::Actions.env_set?
        yield
        puts "::endgroup::" if GitHub::Actions.env_set?
      end

      def output?
        @output.present?
      end

      # The execution time of the task.
      # Precondition: Step#run has been called.
      # @return [Float] execution time in seconds
      def time
        end_time - start_time
      end

      def puts_full_output
        return if @output.blank? || @verbose

        puts_in_github_actions_group("Full #{command_short} output") do
          puts @output
        end
      end

      def annotation_location(name)
        formula = Formulary.factory(name)
        method_sym = command.second.to_sym
        method_location = formula.method(method_sym).source_location if formula.respond_to?(method_sym)

        if method_location.present? && (method_location.first == formula.path.to_s)
          method_location
        else
          [formula.path, nil]
        end
      rescue FormulaUnavailableError
        [@repository.glob("**/#{name}*").first, nil]
      end

      def truncate_output(output, max_kb:, context_lines:)
        output_lines = output.lines
        first_error_index = output_lines.find_index do |line|
          !line.strip.match?(/^::error( .*)?::/) &&
            (line.match?(/\berror:\s+/i) || line.match?(/\bcmake error\b/i))
        end

        if first_error_index.blank?
          output = []

          # Collect up to max_kb worth of the last lines of output.
          output_lines.reverse_each do |line|
            # Check output.present? so that we at least have _some_ output.
            break if line.length + output.join.length > max_kb && output.present?

            output.unshift line
          end

          output.join
        else
          start = [first_error_index - context_lines, 0].max
          # Let GitHub Actions truncate us to 4KB if needed.
          output_lines[start..].join
        end
      end

      def run(dry_run: false, fail_fast: false)
        @start_time = Time.now

        puts_command
        if dry_run
          @status = :passed
          puts_result
          return
        end

        raise "git should always be called with -C!" if command[0] == "git" && %w[-C clone].exclude?(command[1])

        executable, *args = command

        result = system_command executable, args:,
                                            print_stdout: @verbose,
                                            print_stderr: @verbose,
                                            env:          @env

        @end_time = Time.now

        @status = if result.success?
          :passed
        elsif @ignore_failures
          :ignored
        else
          :failed
        end

        puts_result

        output = result.merged_output

        # ActiveSupport can barf on some Unicode so don't use .present?
        if output.empty?
          puts if @verbose
          exit 1 if fail_fast && failed?
          return
        end

        output.force_encoding(Encoding::UTF_8)
        @output = if output.valid_encoding?
          output
        else
          output.encode!(Encoding::UTF_16, invalid: :replace)
          output.encode!(Encoding::UTF_8)
        end

        return if passed?

        puts_full_output

        unless GitHub::Actions.env_set?
          puts
          exit 1 if fail_fast && failed?
          return
        end

        # TODO: move to extend/os
        # rubocop:todo Homebrew/MoveToExtendOS
        os_string = if OS.mac?
          str = "macOS #{MacOS.version.pretty_name} (#{MacOS.version})"
          str << " on Apple Silicon" if Hardware::CPU.arm?

          str
        else
          "#{OS.kernel_name} #{Hardware::CPU.arch}"
        end
        # rubocop:enable Homebrew/MoveToExtendOS

        @named_args.each do |name|
          next if name.blank?

          path, line = annotation_location(name)
          next if path.blank?

          # GitHub Actions has a 4KB maximum for annotations.
          annotation_output = truncate_output(@output, max_kb: 4, context_lines: 5)

          annotation_title = "`#{command_trimmed}` failed on #{os_string}!"
          file = path.to_s.delete_prefix("#{@repository}/")
          puts_in_github_actions_group("Truncated #{command_short} output") do
            puts_github_actions_annotation(annotation_output, annotation_title, file, line)
          end
        end

        exit 1 if fail_fast && failed?
      end
    end
  end
end
