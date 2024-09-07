# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "fetch"
require "cask/download"

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
            formula = T.cast(formula_or_cask, Formula)
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

                    begin
                      bottle.fetch_tab
                    rescue DownloadError
                      retry if retry_fetch?(bottle)
                      raise
                    end
                    fetch_formula(bottle)
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

                fetch_formula(formula)

                formula.resources.each do |r|
                  fetch_resource(r)
                  r.patches.each { |p| fetch_patch(p) if p.external? }
                end

                formula.patchlist.each { |p| fetch_patch(p) if p.external? }
              end
            end
          else
            cask = formula_or_cask
            ref = cask.loaded_from_api? ? cask.full_name : cask.sourcefile_path

            os_arch_combinations.each do |os, arch|
              next if os == :linux

              SimulateSystem.with(os:, arch:) do
                cask = Cask::CaskLoader.load(ref)

                if cask.url.nil? || cask.sha256.nil?
                  opoo "Cask #{cask} is not supported on os #{os} and arch #{arch}"
                  next
                end

                quarantine = args.quarantine?
                quarantine = true if quarantine.nil?

                download = Cask::Download.new(cask, quarantine:)
                fetch_cask(download)
              end
            end
          end
        end
      end

      private

      def fetch_resource(resource)
        puts "Resource: #{resource.name}"
        fetch_fetchable resource
      rescue ChecksumMismatchError => e
        retry if retry_fetch?(resource)
        opoo "Resource #{resource.name} reports different sha256: #{e.expected}"
      end

      def fetch_formula(formula)
        fetch_fetchable(formula)
      rescue ChecksumMismatchError => e
        retry if retry_fetch?(formula)
        opoo "Formula reports different sha256: #{e.expected}"
      end

      def fetch_cask(cask_download)
        fetch_fetchable(cask_download)
      rescue ChecksumMismatchError => e
        retry if retry_fetch?(cask_download)
        opoo "Cask reports different sha256: #{e.expected}"
      end

      def fetch_patch(patch)
        fetch_fetchable(patch)
      rescue ChecksumMismatchError => e
        opoo "Patch reports different sha256: #{e.expected}"
        Homebrew.failed = true
      end

      def retry_fetch?(formula)
        @fetch_tries ||= Hash.new { |h, k| h[k] = 1 }
        if args.retry? && (@fetch_tries[formula] < FETCH_MAX_TRIES)
          wait = 2 ** @fetch_tries[formula]
          remaining = FETCH_MAX_TRIES - @fetch_tries[formula]
          what = Utils.pluralize("tr", remaining, plural: "ies", singular: "y")

          ohai "Retrying download in #{wait}s... (#{remaining} #{what} left)"
          sleep wait

          formula.clear_cache
          @fetch_tries[formula] += 1
          true
        else
          Homebrew.failed = true
          false
        end
      end

      def fetch_fetchable(formula)
        formula.clear_cache if args.force?

        already_fetched = formula.cached_download.exist?

        begin
          download = formula.fetch(verify_download_integrity: false)
        rescue DownloadError
          retry if retry_fetch?(formula)
          raise
        end

        return unless download.file?

        puts "Downloaded to: #{download}" unless already_fetched
        puts "SHA256: #{download.sha256}"

        formula.verify_download_integrity(download)
      end
    end
  end
end
