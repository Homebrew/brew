# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "cask/cask"
require "utils/analytics/package_feeds"

module Homebrew
  module DevCmd
    class GenerateCaskFeeds < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate recent cask additions and updates for <#{HOMEBREW_API_WWW}> feeds.
          Requires a complete `homebrew/cask` Git history.
        EOS
        flag "--output=", description: "Write JSON to this path instead of `_data/cask_feeds.json`."

        named_args :none
        hide_from_man_page!
      end

      sig { override.void }
      def run
        Feeds.write(
          repository: CoreCaskTap.instance.path,
          output: Pathname(args.output || "_data/cask_feeds.json"), kind: "cask"
        )
      end

      # Supplies cask metadata to the shared feed generator.
      class Feeds < Utils::Analytics::PackageFeeds
        sig { override.params(path: String, blob: String, source: String).returns(Builds) }
        def read_builds(path, blob, source)
          cask = T.let(nil, T.nilable(Cask::Cask))
          @history.targets.each do |os, arch|
            cask = Homebrew::SimulateSystem.with(os:, arch:) { Cask::CaskLoader.from_content(source) }
            break
          rescue Cask::CaskInvalidError, Cask::CaskUnreadableError
            next
          end
          if cask.nil? || cask.token != File.basename(path, ".rb")
            raise "Cannot read cask metadata for #{path} at #{blob}"
          end

          @history.targets.to_h do |os, arch|
            version = cask.refresh_for_tag(::Utils::Bottles::Tag.new(system: os, arch:)) do
              cask.version&.to_s
            end
            ["#{os}/#{arch}", Utils::Analytics::FormulaHistory::Build.new(version:)]
          end
        end

        sig { override.params(path: String).returns(T::Boolean) }
        def package_path?(path)
          path = "Casks/#{path.delete_prefix("Cask/")}" if path.start_with?("Cask/")
          CoreCaskTap.instance.cask_file?(path)
        end
      end
    end
  end
end
