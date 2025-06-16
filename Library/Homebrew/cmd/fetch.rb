# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "fetch"
require "cask/download"
require "retryable_download"

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

      def concurrency
        @concurrency ||= args.concurrency&.to_i || 1
      end

      def download_queue
        @download_queue ||= begin
          require "download_queue"
          DownloadQueue.new(concurrency)
        end
      end

      class Spinner
        FRAMES = [
          "⠋",
          "⠙",
          "⠚",
          "⠞",
          "⠖",
          "⠦",
          "⠴",
          "⠲",
          "⠳",
          "⠓",
        ].freeze

        sig { void }
        def initialize
          @start = Time.now
          @i = 0
        end

        sig { returns(String) }
        def to_s
          now = Time.now
          if @start + 0.1 < now
            @start = now
            @i = (@i + 1) % FRAMES.count
          end

          FRAMES.fetch(@i)
        end
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

                    if (manifest_resource = bottle.github_packages_manifest_resource)
                      fetch_downloadable(manifest_resource)
                    end
                    fetch_downloadable(bottle)
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

                fetch_downloadable(formula.resource)

                formula.resources.each do |r|
                  fetch_downloadable(r)
                  r.patches.each { |patch| fetch_downloadable(patch.resource) if patch.external? }
                end

                formula.patchlist.each { |patch| fetch_downloadable(patch.resource) if patch.external? }
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
                fetch_downloadable(download)
              end
            end
          end
        end

        if concurrency == 1
          downloads.each do |downloadable, promise|
            promise.wait!
          rescue ChecksumMismatchError => e
            opoo "#{downloadable.download_type.capitalize} reports different checksum: #{e.expected}"
            Homebrew.failed = true if downloadable.is_a?(Resource::Patch)
          end
        else
          spinner = Spinner.new
          remaining_downloads = downloads.dup
          previous_pending_line_count = 0

          begin
            $stdout.print Tty.hide_cursor
            $stdout.flush

            output_message = lambda do |downloadable, future, last|
              status = case future.state
              when :fulfilled
                "#{Tty.green}✔︎#{Tty.reset}"
              when :rejected
                "#{Tty.red}✘#{Tty.reset}"
              when :pending, :processing
                "#{Tty.blue}#{spinner}#{Tty.reset}"
              else
                raise future.state.to_s
              end

              message = "#{downloadable.download_type.capitalize} #{downloadable.name}"
              $stdout.print "#{status} #{message}#{"\n" unless last}"
              $stdout.flush

              if future.rejected?
                if (e = future.reason).is_a?(ChecksumMismatchError)
                  opoo "#{downloadable.download_type.capitalize} reports different checksum: #{e.expected}"
                  Homebrew.failed = true if downloadable.is_a?(Resource::Patch)
                  next 2
                else
                  message = future.reason.to_s
                  onoe message
                  Homebrew.failed = true
                  next message.count("\n")
                end
              end

              1
            end

            until remaining_downloads.empty?
              begin
                finished_states = [:fulfilled, :rejected]

                finished_downloads, remaining_downloads = remaining_downloads.partition do |_, future|
                  finished_states.include?(future.state)
                end

                finished_downloads.each do |downloadable, future|
                  previous_pending_line_count -= 1
                  $stdout.print Tty.clear_to_end
                  $stdout.flush
                  output_message.call(downloadable, future, false)
                end

                previous_pending_line_count = 0
                max_lines = [concurrency, Tty.height].min
                remaining_downloads.each_with_index do |(downloadable, future), i|
                  break if previous_pending_line_count >= max_lines

                  $stdout.print Tty.clear_to_end
                  $stdout.flush
                  last = i == max_lines - 1 || i == remaining_downloads.count - 1
                  previous_pending_line_count += output_message.call(downloadable, future, last)
                end

                if previous_pending_line_count.positive?
                  if (previous_pending_line_count - 1).zero?
                    $stdout.print Tty.move_cursor_beginning
                  else
                    $stdout.print Tty.move_cursor_up_beginning(previous_pending_line_count - 1)
                  end
                  $stdout.flush
                end

                sleep 0.05
              rescue Interrupt
                remaining_downloads.each do |_, future|
                  # FIXME: Implement cancellation of running downloads.
                end

                download_queue.cancel

                if previous_pending_line_count.positive?
                  $stdout.print Tty.move_cursor_down(previous_pending_line_count - 1)
                  $stdout.flush
                end

                raise
              end
            end
          ensure
            $stdout.print Tty.show_cursor
            $stdout.flush
          end
        end
      ensure
        download_queue.shutdown
      end

      private

      def downloads
        @downloads ||= {}
      end

      def fetch_downloadable(downloadable)
        downloads[downloadable] ||= begin
          tries = args.retry? ? {} : { tries: 1 }
          download_queue.enqueue(RetryableDownload.new(downloadable, **tries), force: args.force?)
        end
      end
    end
  end
end
