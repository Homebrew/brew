# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "utils/analytics/package_feeds"

module Homebrew
  module DevCmd
    class GenerateFormulaFeeds < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate recent formula additions and updates for <#{HOMEBREW_API_WWW}> feeds.
          Requires a complete `homebrew/core` Git history.
        EOS
        flag "--output=", description: "Write JSON to this path instead of `_data/formula_feeds.json`."

        named_args :none
        hide_from_man_page!
      end

      sig { override.void }
      def run
        Feeds.write(
          repository: CoreTap.instance.path,
          output: Pathname(args.output || "_data/formula_feeds.json"), kind: "formula"
        )
      end

      # Supplies formula metadata to the shared feed generator.
      class Feeds < Utils::Analytics::PackageFeeds
        sig { override.params(path: String, blob: String, source: String).returns(Builds) }
        def read_builds(path, blob, source)
          @history.builds(path, source).tap do |builds|
            if builds.values.any?(&:error)
              raise "Cannot read formula metadata for #{path} at #{blob}"
            end
          end
        end

        sig { override.params(path: String).returns(T::Boolean) }
        def package_path?(path)
          CoreTap.instance.formula_file?(path.delete_prefix("Library/"))
        end
      end
    end
  end
end
