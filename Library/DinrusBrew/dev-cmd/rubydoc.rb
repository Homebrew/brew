# typed: strict
# frozen_string_literal: true

require "abstract_command"

module DinrusBrew
  module DevCmd
    class Rubydoc < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate DinrusBrew's RubyDoc documentation.
        EOS
        switch "--only-public",
               description: "Only generate public API documentation."
        switch "--open",
               description: "Open generated documentation in a browser."
      end

      sig { override.void }
      def run
        DinrusBrew.install_bundler_gems!(groups: ["doc"])

        DINRUSBREW_LIBRARY_PATH.cd do |dir|
          no_api_args = if args.only_public?
            ["--hide-api", "private", "--hide-api", "internal"]
          else
            []
          end

          output_dir = dir/"doc"

          safe_system "bundle", "exec", "yard", "doc", "--fail-on-warning", *no_api_args, "--output", output_dir

          exec_browser "file://#{output_dir}/index.html" if args.open?
        end
      end
    end
  end
end
