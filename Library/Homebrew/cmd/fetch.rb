# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "fetch"
require "api/cask_download"
require "api/formula_bottle"
require "cask/config"
require "cask/download"
require "download_queue"

module Homebrew
  module Cmd
    class FetchCmd < AbstractCommand
      include Fetch

      FETCH_MAX_TRIES = 5

      cmd_args do
        description <<~EOS
          Download a bottle (if available) or source packages for <formula>e
          and binaries for <cask>s. For files, also print SHA-256 checksums.
        EOS
        flag   "--os=",
               description: "Download for the given operating system. " \
                            "(Pass `all` to download for all operating systems.)"
        flag   "--arch=",
               description: "Download for the given CPU architecture. " \
                            "(Pass `all` to download for all architectures.)"
        switch "--all-platforms",
               description: "Download for every supported operating system and architecture, plus each " \
                            "language for <cask>s, fetching each distinct URL once."
        flag   "--bottle-tag=",
               description: "Download a bottle for given tag."
        switch "--HEAD",
               description: "Fetch HEAD version instead of stable version."
        switch "-f", "--force",
               description: "Remove a previously cached version and re-fetch."
        switch "-v", "--verbose",
               description: "Do a verbose VCS checkout, if the URL represents a VCS. This is useful for " \
                            "seeing if an existing VCS cache has been updated."
        switch "--retry",
               description: "Retry if downloading fails or re-download if the checksum of a previously cached " \
                            "version no longer matches. Tries at most #{FETCH_MAX_TRIES} times with " \
                            "exponential backoff."
        switch "--deps",
               description: "Also download dependencies for any listed <formula>."
        switch "-s", "--build-from-source",
               description: "Download source packages rather than a bottle."
        switch "--build-bottle",
               description: "Download source packages (for eventual bottling) rather than a bottle."
        switch "--force-bottle",
               description: "Download a bottle if it exists for the current or newest version of macOS, " \
                            "even if it would not be used during installation."
        switch "--formula", "--formulae",
               description: "Treat all named arguments as formulae."
        switch "--cask", "--casks",
               description: "Treat all named arguments as casks."

        conflicts "--build-from-source", "--build-bottle", "--force-bottle", "--bottle-tag"
        conflicts "--cask", "--HEAD"
        conflicts "--cask", "--deps"
        conflicts "--cask", "-s"
        conflicts "--cask", "--build-bottle"
        conflicts "--cask", "--force-bottle"
        conflicts "--cask", "--bottle-tag"
        conflicts "--formula", "--cask"
        conflicts "--os", "--bottle-tag"
        conflicts "--arch", "--bottle-tag"
        conflicts "--all-platforms", "--os"
        conflicts "--all-platforms", "--arch"
        conflicts "--all-platforms", "--bottle-tag"

        named_args [:formula, :cask], min: 1
      end

      sig { override.void }
      def run
        Formulary.enable_factory_cache!

        if enqueue_api_formula_bottles? || enqueue_api_cask_downloads?
          download_queue.fetch
          return
        end

        bucket = if args.deps?
          args.named.to_formulae_and_casks.flat_map do |formula_or_cask|
            case formula_or_cask
            when Formula
              formula = formula_or_cask
              [formula, *formula.recursive_dependencies.map(&:to_formula)]
            else
              formula_or_cask
            end
          end
        else
          args.named.to_formulae_and_casks
        end.uniq

        os_arch_combinations = args.os_arch_combinations

        puts "Fetching: #{bucket * ", "}" if bucket.size > 1
        bucket.each do |formula_or_cask|
          case formula_or_cask
          when Formula
            formula = formula_or_cask
            ref = formula.reloadable_ref

            os_arch_combinations.each do |os, arch|
              SimulateSystem.with(os:, arch:) do
                formula = Formulary.factory(ref, args.HEAD? ? :head : :stable)

                formula.print_tap_action verb: "Fetching"

                fetched_bottle = false
                if fetch_bottle?(
                  formula,
                  force_bottle:               args.force_bottle?,
                  bottle_tag:                 args.bottle_tag&.to_sym,
                  build_from_source_formulae: args.build_from_source_formulae,
                  os:                         args.os&.to_sym,
                  arch:                       args.arch&.to_sym,
                )
                  begin
                    formula.clear_cache if args.force?

                    bottle_tag = Utils::Bottles::Tag.from_arg(args.bottle_tag&.to_sym, os:, arch:)

                    bottle = formula.bottle_for_tag(bottle_tag)

                    if bottle.nil?
                      opoo "Bottle for tag #{bottle_tag.to_sym.inspect} is unavailable."
                      next
                    end

                    if (manifest_resource = bottle.github_packages_manifest_resource)
                      download_queue.enqueue(manifest_resource)
                    end
                    download_queue.enqueue(bottle)
                  rescue Interrupt
                    raise
                  rescue => e
                    raise if Homebrew::EnvConfig.developer?

                    fetched_bottle = false
                    onoe e.message
                    opoo "Bottle fetch failed, fetching the source instead."
                  else
                    fetched_bottle = true
                  end
                end

                next if fetched_bottle

                if (resource = formula.resource)
                  download_queue.enqueue(resource)
                end

                formula.enqueue_resources_and_patches(download_queue:)
              end
            end
          when Cask::Cask
            cask_downloads(formula_or_cask).each { |download| download_queue.enqueue(download) }
          else
            odie "Invalid formula or cask: #{formula_or_cask}"
          end
        end

        download_queue.fetch
      ensure
        download_queue.shutdown
      end

      private

      sig { returns(T::Boolean) }
      def enqueue_api_formula_bottles?
        return false unless api_fetchable?
        return false if args.only_formula_or_cask == :cask
        return false if args.deps? || args.HEAD?
        return false if args.build_from_source? || args.build_bottle?
        return false if args.bottle_tag.present?

        names = api_fetch_names(
          regex:   HOMEBREW_DEFAULT_TAP_FORMULA_REGEX,
          capture: :name,
          hashes:  Homebrew::API::Internal.formula_hashes,
          aliases: Homebrew::API::Internal.formula_aliases,
          renames: Homebrew::API::Internal.formula_renames,
        )
        return false if names.nil?

        bottles = T.let([], T::Array[[String, Bottle]])
        bottle_tag = Utils::Bottles.tag
        names.each do |name|
          formula_struct = Homebrew::API::Internal.formula_struct(name)
          return false if formula_struct.pour_bottle?

          bottle = Homebrew::API::FormulaBottle.bottle(name:, formula_struct:, bottle_tag:)
          return false if bottle.nil?
          return false if !args.force_bottle? && !bottle.compatible_locations?

          bottles << [name, bottle]
        end

        puts "Fetching: #{names * ", "}" if names.size > 1
        bottles.each do |name, bottle|
          ohai "Fetching #{name} from #{CoreTap.instance}"
          bottle.clear_cache if args.force?

          if (manifest_resource = bottle.github_packages_manifest_resource)
            download_queue.enqueue(manifest_resource)
          end
          download_queue.enqueue(bottle)
        end
        true
      end

      sig { returns(T::Boolean) }
      def enqueue_api_cask_downloads?
        return false unless api_fetchable?
        return false if args.only_formula_or_cask != :cask

        tokens = api_fetch_names(
          regex:   HOMEBREW_DEFAULT_TAP_CASK_REGEX,
          capture: :token,
          hashes:  Homebrew::API::Internal.cask_hashes,
          aliases: {},
          renames: Homebrew::API::Internal.cask_renames,
        )
        return false if tokens.nil?

        downloads = T.let([], T::Array[[String, Cask::Download]])
        tokens.each do |token|
          download = Homebrew::API::CaskDownload.download(
            token:,
            cask_struct: Homebrew::API::Internal.cask_struct(token),
            quarantine:  true,
            require_sha: Homebrew::EnvConfig.cask_opts_require_sha?,
          )
          return false if download.nil?

          downloads << [token, download]
        end

        puts "Fetching: #{tokens * ", "}" if tokens.size > 1
        downloads.each do |token, download|
          ohai "Fetching #{token} from #{CoreCaskTap.instance}"
          download_queue.enqueue(download)
        end
        true
      end

      sig { returns(T::Boolean) }
      def api_fetchable?
        return false if Homebrew::EnvConfig.no_install_from_api?
        return false if args.all_platforms? || args.os.present? || args.arch.present?
        return false if ENV["HOMEBREW_TEST_GENERIC_OS"].present?

        true
      end

      sig {
        params(
          regex:   Regexp,
          capture: Symbol,
          hashes:  T::Hash[String, T::Hash[String, T.untyped]],
          aliases: T::Hash[String, String],
          renames: T::Hash[String, String],
        ).returns(T.nilable(T::Array[String]))
      }
      def api_fetch_names(regex:, capture:, hashes:, aliases:, renames:)
        requested_names = args.named.downcased_unique_named
        names = T.let(requested_names.filter_map do |requested_name|
          name = requested_name[regex, capture]
          next if name.blank?

          name = name.downcase
          name = aliases.fetch(name, name)
          name = renames.fetch(name, name)
          next unless hashes.key?(name)

          name
        end, T::Array[String])
        return if names.length != requested_names.length

        names
      end

      sig { params(cask: Cask::Cask).returns(T::Array[Cask::Download]) }
      def cask_downloads(cask)
        ref = cask.reloadable_ref

        if args.all_platforms? && cask.loaded_from_api?
          opoo "Cask #{cask} was loaded from the API; cannot fetch all operating system and " \
               "architecture variants. Set `HOMEBREW_NO_INSTALL_FROM_API=1` to fetch them all."
        end

        # With `--all-platforms`, a cask without `on_system` blocks resolves
        # identically everywhere, so one combination covers the whole matrix.
        cask_combinations = args.os_arch_combinations
        cask_combinations = cask_combinations.first(1) if args.all_platforms? && !cask.on_system_blocks_exist?

        downloads = T.let([], T::Array[Cask::Download])
        enqueued_urls = Set.new

        cask_combinations.each do |os, arch|
          SimulateSystem.with(os:, arch:) do
            loaded_cask = begin
              Cask::CaskLoader.load(ref)
            rescue Cask::CaskInvalidError, Cask::CaskUnreadableError
              raise unless cask.on_system_blocks_exist?
            end
            if loaded_cask.nil?
              opoo "Cask #{cask} is not supported on os #{os} and arch #{arch}"
              next
            end

            languages = (loaded_cask.languages if args.all_platforms?)
            languages = [nil] if languages.blank?

            languages.each do |language|
              localized_cask = loaded_cask
              if language
                # Reload per language: `Cask::Download` reads `sha256`/`url`
                # lazily, so each download needs its own cask instance.
                localized_cask = Cask::CaskLoader.load(ref)
                localized_cask.config = localized_cask.config.merge(
                  Cask::Config.new(explicit: { languages: [language] }),
                )
              end

              if localized_cask.url.nil? || localized_cask.sha256.nil?
                opoo "Cask #{cask} is not supported on os #{os} and arch #{arch}"
                next
              end

              next unless enqueued_urls.add?(localized_cask.url.to_s)

              downloads << Cask::Download.new(
                localized_cask,
                quarantine:  true,
                require_sha: Homebrew::EnvConfig.cask_opts_require_sha?,
              )
            end
          end
        end

        downloads
      end

      sig { returns(Integer) }
      def retries
        @retries ||= T.let(args.retry? ? FETCH_MAX_TRIES : 1, T.nilable(Integer))
      end

      sig { returns(DownloadQueue) }
      def download_queue
        @download_queue ||= T.let(begin
          DownloadQueue.new(retries:, force: args.force?)
        end, T.nilable(DownloadQueue))
      end
    end
  end
end
