# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "fetch"
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
        flag   "--bottle-tag=",
               description: "Download a bottle for given tag."
        flag "--concurrency=", description: "Number of concurrent downloads.", hidden: true
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
        switch "--[no-]quarantine",
               description: "Disable/enable quarantining of downloads (default: enabled).",
               env:         :cask_opts_quarantine
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

        named_args [:formula, :cask], min: 1
      end

      sig { override.void }
      def run
        Formulary.enable_factory_cache!

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
            ref = formula.loaded_from_api? ? formula.full_name : formula.path

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

                    bottle_tag = if (bottle_tag = args.bottle_tag&.to_sym)
                      Utils::Bottles::Tag.from_symbol(bottle_tag)
                    else
                      Utils::Bottles::Tag.new(system: os, arch:)
                    end

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

                formula.resources.each do |r|
                  download_queue.enqueue(r)
                  r.patches.each { |patch| download_queue.enqueue(patch.resource) if patch.external? }
                end

                formula.patchlist.each { |patch| download_queue.enqueue(patch.resource) if patch.external? }
              end
            end
          else
            cask = formula_or_cask
            ref = cask.loaded_from_api? ? cask.full_name : cask.sourcefile_path

            os_arch_combinations.each do |os, arch|
              SimulateSystem.with(os:, arch:) do
                cask = Cask::CaskLoader.load(ref)

                if cask.url.nil? || cask.sha256.nil?
                  opoo "Cask #{cask} is not supported on os #{os} and arch #{arch}"
                  next
                end

                quarantine = args.quarantine?
                quarantine = true if quarantine.nil?

                download = Cask::Download.new(cask, quarantine:)
                download_queue.enqueue(download)
              end
            end
          end
        end

        download_queue.start
      ensure
        download_queue.shutdown
      end

      private

      sig { returns(Integer) }
      def concurrency
        @concurrency ||= T.let(args.concurrency&.to_i || 1, T.nilable(Integer))
      end

      sig { returns(Integer) }
      def retries
        @retries ||= T.let(args.retry? ? FETCH_MAX_TRIES : 0, T.nilable(Integer))
      end

      sig { returns(DownloadQueue) }
      def download_queue
        @download_queue ||= T.let(begin
          DownloadQueue.new(concurrency:, retries:, force: args.force?)
        end, T.nilable(DownloadQueue))
      end
    end
  end
end
