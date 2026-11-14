# typed: strict
# frozen_string_literal: true

module Homebrew
  module Livecheck
    # Displays and clears progress without writing to the JSON output stream.
    class Progress
      sig { params(total: Integer, enabled: T::Boolean).void }
      def initialize(total:, enabled:)
        return unless enabled

        Tty.with($stderr) do |stderr|
          stderr.puts Formatter.headline("Running checks", color: :blue)
        end

        require "ruby-progressbar"
        @bar = T.let(ProgressBar.create(
                       total:,
                       progress_mark:  "#",
                       remainder_mark: ".",
                       format:         " %t: [%B] %c/%C ",
                       output:         $stderr,
                     ), T.nilable(ProgressBar::Base))
      end

      sig { void }
      def increment
        @bar&.increment
      end

      sig { void }
      def finish
        bar = @bar
        return unless bar

        bar.finish
        Tty.with($stderr) do |stderr|
          erase = "#{Tty.up}#{Tty.erase_line}" * 2
          stderr.print "#{Tty.begin_synchronized_update}#{erase}#{Tty.end_synchronized_update}" unless erase.empty?
        end
      end
    end
  end
end
