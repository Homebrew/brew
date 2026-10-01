# typed: strict
# frozen_string_literal: true

require "system_command"
require "utils/browser"

require "abstract_command"

module Homebrew
  module DevCmd
    class Rubydoc < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate Homebrew's RubyDoc documentation.
        EOS
        switch "--only-public",
               description: "Only generate public API documentation."
        switch "--open",
               description: "Open generated documentation in a browser."
      end

      sig { override.void }
      def run
        Utils::GemSetup.install_bundler_gems!(groups: ["doc"])

        HOMEBREW_LIBRARY_PATH.cd do |dir|
          no_api_args = if args.only_public?
            ["--hide-api", "private", "--hide-api", "internal"]
          else
            []
          end

          output_dir = dir/"doc"

          SystemCommand.safe_system "bundle", "exec", "yard", "doc", "--fail-on-warning", *no_api_args, "--output",
                                    output_dir

          Utils::Browser.open "file://#{output_dir}/index.html" if args.open?
        end
      end
    end
  end
end
