# typed: true
# frozen_string_literal: true

require "livecheck/error"
require "livecheck/livecheck_version"
require "livecheck/skip_conditions"
require "livecheck/strategy"
require "ruby-progressbar"
require "uri"

module Homebrew
  # rubocop:disable Metrics/ModuleLength

  # The {Livecheck} module consists of methods used by the `brew livecheck`
  # command. These methods print the requested livecheck information
  # for formulae.
  #
  # @api private
  module Livecheck
    extend T::Sig

    module_function

    GITEA_INSTANCES = %w[
      codeberg.org
      gitea.com
      opendev.org
      tildegit.org
    ].freeze

    GOGS_INSTANCES = %w[
      lolg.it
    ].freeze

    STRATEGY_SYMBOLS_TO_SKIP_PREPROCESS_URL = [
      :github_latest,
      :page_match,
      :header_match,
      :sparkle,
    ].freeze

    UNSTABLE_VERSION_KEYWORDS = %w[
      alpha
      beta
      bpo
      dev
      experimental
      prerelease
      preview
      rc
    ].freeze

    sig { returns(T::Hash[Class, String]) }
    def livecheck_strategy_names
      return @livecheck_strategy_names if defined?(@livecheck_strategy_names)

      # Cache demodulized strategy names, to avoid repeating this work
      @livecheck_strategy_names = {}
      Strategy.constants.sort.each do |strategy_symbol|
        strategy = Strategy.const_get(strategy_symbol)
        @livecheck_strategy_names[strategy] = strategy.name.demodulize
      end
      @livecheck_strategy_names.freeze
    end

    # Uses `formulae_and_casks_to_check` to identify taps in use other than
    # homebrew/core and homebrew/cask and loads strategies from them.
    sig { params(formulae_and_casks_to_check: T::Array[T.any(Formula, Cask::Cask)]).void }
    def load_other_tap_strategies(formulae_and_casks_to_check)
      other_taps = {}
      formulae_and_casks_to_check.each do |formula_or_cask|
        next if formula_or_cask.tap.blank?
        next if formula_or_cask.tap.name == CoreTap.instance.name
        next if formula_or_cask.tap.name == "homebrew/cask"
        next if other_taps[formula_or_cask.tap.name]

        other_taps[formula_or_cask.tap.name] = formula_or_cask.tap
      end
      other_taps = other_taps.sort.to_h

      other_taps.each_value do |tap|
        tap_strategy_path = "#{tap.path}/livecheck/strategy"
        Dir["#{tap_strategy_path}/*.rb"].sort.each(&method(:require)) if Dir.exist?(tap_strategy_path)
      end
    end

    # Resolve formula/cask references in `livecheck` blocks to a final formula
    # or cask.
    sig {
      params(
        formula_or_cask:       T.any(Formula, Cask::Cask),
        first_formula_or_cask: T.any(Formula, Cask::Cask),
        references:            T::Array[T.any(Formula, Cask::Cask)],
        full_name:             T::Boolean,
        debug:                 T::Boolean,
      ).returns(T.nilable(T::Array[T.untyped]))
    }
    def resolve_livecheck_reference(
      formula_or_cask,
      first_formula_or_cask = formula_or_cask,
      references = [],
      full_name: false,
      debug: false
    )
      livecheck = formula_or_cask.livecheck
      livecheck_formula = livecheck.formula
      livecheck_cask = livecheck.cask
      return [nil, references] if livecheck_formula.blank? && livecheck_cask.blank?

      livecheck_formula_or_cask = if livecheck_formula
        Formulary.factory(livecheck_formula)
      elsif livecheck_cask
        Cask::CaskLoader.load(livecheck_cask)
      end

      # Error if a `livecheck` block references a formula/cask that was already
      # referenced (or itself)
      if livecheck_formula_or_cask == first_formula_or_cask ||
         livecheck_formula_or_cask == formula_or_cask ||
         references.include?(livecheck_formula_or_cask)
        if debug
          # Print the chain of references for debugging
          puts "Reference Chain:"
          puts formula_or_cask_name(first_formula_or_cask, full_name: full_name)

          references << livecheck_formula_or_cask
          references.each do |ref_formula_or_cask|
            puts formula_or_cask_name(ref_formula_or_cask, full_name: full_name)
          end
        end

        raise "Circular formula/cask reference encountered"
      end

      references << livecheck_formula_or_cask
      next_livecheck_formula_or_cask, next_references = resolve_livecheck_reference(
        livecheck_formula_or_cask,
        first_formula_or_cask,
        references,
        full_name: full_name,
        debug:     debug,
      )

      # Returning the references allows us to print the chain of references in
      # the debug output
      [
        next_livecheck_formula_or_cask || livecheck_formula_or_cask,
        next_references,
      ]
    end

    # Executes the livecheck logic for each formula/cask in the
    # `formulae_and_casks_to_check` array and prints the results.
    sig {
      params(
        formulae_and_casks_to_check: T::Array[T.any(Formula, Cask::Cask)],
        full_name:                   T::Boolean,
        handle_name_conflict:        T::Boolean,
        json:                        T::Boolean,
        newer_only:                  T::Boolean,
        debug:                       T::Boolean,
        quiet:                       T::Boolean,
        verbose:                     T::Boolean,
      ).void
    }
    def run_checks(
      formulae_and_casks_to_check,
      full_name: false, handle_name_conflict: false, json: false, newer_only: false,
      debug: false, quiet: false, verbose: false
    )
      load_other_tap_strategies(formulae_and_casks_to_check)

      ambiguous_casks = []
      if handle_name_conflict
        ambiguous_casks = formulae_and_casks_to_check.group_by { |item| formula_or_cask_name(item, full_name: true) }
                                                     .values
                                                     .select { |items| items.length > 1 }
                                                     .flatten
                                                     .select { |item| item.is_a?(Cask::Cask) }
      end

      ambiguous_names = []
      unless full_name
        ambiguous_names =
          (formulae_and_casks_to_check - ambiguous_casks).group_by { |item| formula_or_cask_name(item) }
                                                         .values
                                                         .select { |items| items.length > 1 }
                                                         .flatten
      end

      has_a_newer_upstream_version = T.let(false, T::Boolean)

      if json && !quiet && $stderr.tty?
        formulae_and_casks_total = formulae_and_casks_to_check.count

        Tty.with($stderr) do |stderr|
          stderr.puts Formatter.headline("Running checks", color: :blue)
        end

        progress = ProgressBar.create(
          total:          formulae_and_casks_total,
          progress_mark:  "#",
          remainder_mark: ".",
          format:         " %t: [%B] %c/%C ",
          output:         $stderr,
        )
      end

      # rubocop:disable Metrics/BlockLength
      formulae_checked = formulae_and_casks_to_check.map.with_index do |formula_or_cask, i|
        formula = formula_or_cask if formula_or_cask.is_a?(Formula)
        cask = formula_or_cask if formula_or_cask.is_a?(Cask::Cask)

        use_full_name = full_name || ambiguous_names.include?(formula_or_cask)
        name = formula_or_cask_name(formula_or_cask, full_name: use_full_name)

        livecheck_formula_or_cask, livecheck_references =
          resolve_livecheck_reference(formula_or_cask, full_name: use_full_name, debug: debug)

        if debug && i.positive?
          puts <<~EOS

            ----------

          EOS
        elsif debug
          puts
        end

        # Check skip conditions for a referenced formula/cask
        if livecheck_formula_or_cask
          skip_info = SkipConditions.referenced_skip_information(
            livecheck_formula_or_cask,
            name,
            full_name: use_full_name,
            verbose:   verbose,
          )
        end

        skip_info ||= SkipConditions.skip_information(formula_or_cask, full_name: use_full_name, verbose: verbose)
        if skip_info.present?
          next skip_info if json

          SkipConditions.print_skip_information(skip_info) unless quiet
          next
        end

        formula&.head&.downloader&.shutup!

        # Use the `stable` version for comparison except for installed
        # head-only formulae. A formula with `stable` and `head` that's
        # installed using `--head` will still use the `stable` version for
        # comparison.
        current = if formula
          if formula.head_only?
            formula.any_installed_version.version.commit
          else
            formula.stable.version
          end
        else
          Version.new(formula_or_cask.version)
        end

        current_str = current.to_s
        current = LivecheckVersion.create(formula_or_cask, current)

        latest = if formula&.head_only?
          formula.head.downloader.fetch_last_commit
        else
          version_info = latest_version(
            formula_or_cask,
            livecheck_formula_or_cask: livecheck_formula_or_cask,
            livecheck_references: livecheck_references,
            json: json, full_name: use_full_name, verbose: verbose, debug: debug
          )
          version_info[:latest] if version_info.present?
        end

        if latest.blank?
          no_versions_msg = "Unable to get versions"
          raise Livecheck::Error, no_versions_msg unless json

          next version_info if version_info.is_a?(Hash) && version_info[:status] && version_info[:messages]

          next status_hash(formula_or_cask, "error", [no_versions_msg], full_name: use_full_name, verbose: verbose)
        end

        if (m = latest.to_s.match(/(.*)-release$/)) && !current.to_s.match(/.*-release$/)
          latest = Version.new(m[1])
        end

        latest_str = latest.to_s
        latest = LivecheckVersion.create(formula_or_cask, latest)

        is_outdated = if formula&.head_only?
          # A HEAD-only formula is considered outdated if the latest upstream
          # commit hash is different than the installed version's commit hash
          (current != latest)
        else
          (current < latest)
        end

        is_newer_than_upstream = (formula&.stable? || cask) && (current > latest)

        info = {}
        info[:formula] = name if formula
        info[:cask] = name if cask
        info[:version] = {
          current:             current_str,
          latest:              latest_str,
          outdated:            is_outdated,
          newer_than_upstream: is_newer_than_upstream,
        }
        info[:meta] = {
          livecheckable: formula_or_cask.livecheckable?,
        }
        info[:meta][:head_only] = true if formula&.head_only?
        info[:meta].merge!(version_info[:meta]) if version_info.present? && version_info.key?(:meta)

        next if newer_only && !info[:version][:outdated]

        has_a_newer_upstream_version ||= true

        if json
          progress&.increment
          info.except!(:meta) unless verbose
          next info
        end

        print_latest_version(info, verbose: verbose, ambiguous_cask: ambiguous_casks.include?(formula_or_cask))
        nil
      rescue => e
        Homebrew.failed = true
        use_full_name = full_name || ambiguous_names.include?(formula_or_cask)

        if json
          progress&.increment
          status_hash(formula_or_cask, "error", [e.to_s], full_name: use_full_name, verbose: verbose)
        elsif !quiet
          name = formula_or_cask_name(formula_or_cask, full_name: use_full_name)
          name += " (cask)" if ambiguous_casks.include?(formula_or_cask)

          onoe "#{Tty.blue}#{name}#{Tty.reset}: #{e}"
          $stderr.puts e.backtrace if debug && !e.is_a?(Livecheck::Error)
          nil
        end
      end
      # rubocop:enable Metrics/BlockLength

      puts "No newer upstream versions." if newer_only && !has_a_newer_upstream_version && !debug && !json

      return unless json

      if progress
        progress.finish
        Tty.with($stderr) do |stderr|
          stderr.print "#{Tty.up}#{Tty.erase_line}" * 2
        end
      end

      puts JSON.pretty_generate(formulae_checked.compact)
    end

    sig { params(formula_or_cask: T.any(Formula, Cask::Cask), full_name: T::Boolean).returns(String) }
    def formula_or_cask_name(formula_or_cask, full_name: false)
      case formula_or_cask
      when Formula
        formula_name(formula_or_cask, full_name: full_name)
      when Cask::Cask
        cask_name(formula_or_cask, full_name: full_name)
      else
        T.absurd(formula_or_cask)
      end
    end

    # Returns the fully-qualified name of a cask if the `full_name` argument is
    # provided; returns the name otherwise.
    sig { params(cask: Cask::Cask, full_name: T::Boolean).returns(String) }
    def cask_name(cask, full_name: false)
      full_name ? cask.full_name : cask.token
    end

    # Returns the fully-qualified name of a formula if the `full_name` argument is
    # provided; returns the name otherwise.
    sig { params(formula: Formula, full_name: T::Boolean).returns(String) }
    def formula_name(formula, full_name: false)
      full_name ? formula.full_name : formula.name
    end

    sig {
      params(
        formula_or_cask: T.any(Formula, Cask::Cask),
        status_str:      String,
        messages:        T.nilable(T::Array[String]),
        full_name:       T::Boolean,
        verbose:         T::Boolean,
      ).returns(Hash)
    }
    def status_hash(formula_or_cask, status_str, messages = nil, full_name: false, verbose: false)
      formula = formula_or_cask if formula_or_cask.is_a?(Formula)
      cask = formula_or_cask if formula_or_cask.is_a?(Cask::Cask)

      status_hash = {}
      if formula
        status_hash[:formula] = formula_name(formula, full_name: full_name)
      elsif cask
        status_hash[:cask] = cask_name(formula_or_cask, full_name: full_name)
      end
      status_hash[:status] = status_str
      status_hash[:messages] = messages if messages.is_a?(Array)

      status_hash[:meta] = {
        livecheckable: formula_or_cask.livecheckable?,
      }
      status_hash[:meta][:head_only] = true if formula&.head_only?

      status_hash
    end

    # Formats and prints the livecheck result for a formula.
    sig { params(info: Hash, verbose: T::Boolean, ambiguous_cask: T::Boolean).void }
    def print_latest_version(info, verbose:, ambiguous_cask: false)
      formula_or_cask_s = "#{Tty.blue}#{info[:formula] || info[:cask]}#{Tty.reset}"
      formula_or_cask_s += " (cask)" if ambiguous_cask
      formula_or_cask_s += " (guessed)" if !info[:meta][:livecheckable] && verbose

      current_s = if info[:version][:newer_than_upstream]
        "#{Tty.red}#{info[:version][:current]}#{Tty.reset}"
      else
        info[:version][:current]
      end

      latest_s = if info[:version][:outdated]
        "#{Tty.green}#{info[:version][:latest]}#{Tty.reset}"
      else
        info[:version][:latest]
      end

      puts "#{formula_or_cask_s} : #{current_s} ==> #{latest_s}"
    end

    sig {
      params(
        livecheck_url:   T.any(String, Symbol),
        formula_or_cask: T.any(Formula, Cask::Cask),
      ).returns(T.nilable(String))
    }
    def livecheck_url_to_string(livecheck_url, formula_or_cask)
      case livecheck_url
      when String
        livecheck_url
      when :url
        formula_or_cask.url&.to_s if formula_or_cask.is_a?(Cask::Cask)
      when :head, :stable
        formula_or_cask.send(livecheck_url)&.url if formula_or_cask.is_a?(Formula)
      when :homepage
        formula_or_cask.homepage
      end
    end

    # Returns an Array containing the formula/cask URLs that can be used by livecheck.
    sig { params(formula_or_cask: T.any(Formula, Cask::Cask)).returns(T::Array[String]) }
    def checkable_urls(formula_or_cask)
      urls = []

      case formula_or_cask
      when Formula
        if formula_or_cask.stable
          urls << formula_or_cask.stable.url
          urls.concat(formula_or_cask.stable.mirrors)
        end
        urls << formula_or_cask.head.url if formula_or_cask.head
        urls << formula_or_cask.homepage if formula_or_cask.homepage
      when Cask::Cask
        urls << formula_or_cask.appcast.to_s if formula_or_cask.appcast
        urls << formula_or_cask.url.to_s if formula_or_cask.url
        urls << formula_or_cask.homepage if formula_or_cask.homepage
      else
        T.absurd(formula_or_cask)
      end

      urls.compact
    end

    # Preprocesses and returns the URL used by livecheck.
    sig { params(url: String).returns(String) }
    def preprocess_url(url)
      begin
        uri = URI.parse url
      rescue URI::InvalidURIError
        return url
      end

      host = uri.host
      path = uri.path
      return url if host.nil? || path.nil?

      host = "github.com" if host == "github.s3.amazonaws.com"
      path = path.delete_prefix("/").delete_suffix(".git")
      scheme = uri.scheme

      if host.end_with?("github.com")
        return url if path.match? %r{/releases/latest/?$}

        owner, repo = path.delete_prefix("downloads/").split("/")
        url = "#{scheme}://#{host}/#{owner}/#{repo}.git"
      elsif host.end_with?(*GITEA_INSTANCES)
        return url if path.match? %r{/releases/latest/?$}

        owner, repo = path.split("/")
        url = "#{scheme}://#{host}/#{owner}/#{repo}.git"
      elsif host.end_with?(*GOGS_INSTANCES)
        owner, repo = path.split("/")
        url = "#{scheme}://#{host}/#{owner}/#{repo}.git"
      # sourcehut
      elsif host.end_with?("git.sr.ht")
        owner, repo = path.split("/")
        url = "#{scheme}://#{host}/#{owner}/#{repo}"
      # GitLab (gitlab.com or self-hosted)
      elsif path.include?("/-/archive/")
        url = url.sub(%r{/-/archive/.*$}i, ".git")
      end

      url
    end

    # Identifies the latest version of the formula and returns a Hash containing
    # the version information. Returns nil if a latest version couldn't be found.
    sig {
      params(
        formula_or_cask:           T.any(Formula, Cask::Cask),
        livecheck_formula_or_cask: T.nilable(T.any(Formula, Cask::Cask)),
        livecheck_references:      T::Array[T.any(Formula, Cask::Cask)],
        json:                      T::Boolean,
        full_name:                 T::Boolean,
        verbose:                   T::Boolean,
        debug:                     T::Boolean,
      ).returns(T.nilable(Hash))
    }
    def latest_version(
      formula_or_cask,
      livecheck_formula_or_cask: nil,
      livecheck_references: [],
      json: false, full_name: false, verbose: false, debug: false
    )
      formula = formula_or_cask if formula_or_cask.is_a?(Formula)
      cask = formula_or_cask if formula_or_cask.is_a?(Cask::Cask)

      has_livecheckable = formula_or_cask.livecheckable?
      livecheck = formula_or_cask.livecheck

      livecheck_formula_or_cask_livecheck = livecheck_formula_or_cask&.livecheck

      livecheck_url = livecheck.url || livecheck_formula_or_cask_livecheck&.url
      livecheck_regex = livecheck.regex || livecheck_formula_or_cask_livecheck&.regex
      livecheck_strategy = livecheck.strategy || livecheck_formula_or_cask_livecheck&.strategy
      livecheck_strategy_block = livecheck.strategy_block || livecheck_formula_or_cask_livecheck&.strategy_block

      livecheck_url_string = livecheck_url_to_string(
        livecheck_url,
        livecheck_formula_or_cask || formula_or_cask,
      )

      urls = [livecheck_url_string] if livecheck_url_string
      urls ||= checkable_urls(livecheck_formula_or_cask || formula_or_cask)

      if debug
        if formula
          puts "Formula:          #{formula_name(formula, full_name: full_name)}"
          puts "Head only?:       true" if formula.head_only?
        elsif cask
          puts "Cask:             #{cask_name(formula_or_cask, full_name: full_name)}"
        end
        puts "Livecheckable?:   #{has_livecheckable ? "Yes" : "No"}"

        livecheck_references.each do |ref_formula_or_cask|
          case ref_formula_or_cask
          when Formula
            puts "Formula Ref:      #{formula_name(ref_formula_or_cask, full_name: full_name)}"
          when Cask::Cask
            puts "Cask Ref:         #{cask_name(ref_formula_or_cask, full_name: full_name)}"
          end
        end
      end

      # rubocop:disable Metrics/BlockLength
      urls.each_with_index do |original_url, i|
        if debug
          puts
          if livecheck_url.is_a?(Symbol)
            # This assumes the URL symbol will fit within the available space
            puts "URL (#{livecheck_url}):".ljust(18, " ") + original_url
          else
            puts "URL:              #{original_url}"
          end
        end

        # Only preprocess the URL when it's appropriate
        url = if STRATEGY_SYMBOLS_TO_SKIP_PREPROCESS_URL.include?(livecheck_strategy)
          original_url
        else
          preprocess_url(original_url)
        end

        strategies = Strategy.from_url(
          url,
          livecheck_strategy: livecheck_strategy,
          url_provided:       livecheck_url.present?,
          regex_provided:     livecheck_regex.present?,
          block_provided:     livecheck_strategy_block.present?,
        )
        strategy = Strategy.from_symbol(livecheck_strategy) || strategies.first
        strategy_name = livecheck_strategy_names[strategy]

        if debug
          puts "URL (processed):  #{url}" if url != original_url
          if strategies.present? && verbose
            puts "Strategies:       #{strategies.map { |s| livecheck_strategy_names[s] }.join(", ")}"
          end
          puts "Strategy:         #{strategy.blank? ? "None" : strategy_name}"
          puts "Regex:            #{livecheck_regex.inspect}" if livecheck_regex.present?
        end

        if livecheck_strategy.present?
          if livecheck_strategy == :page_match && (livecheck_regex.blank? && livecheck_strategy_block.blank?)
            odebug "#{strategy_name} strategy requires a regex or block"
            next
          elsif livecheck_url.blank?
            odebug "#{strategy_name} strategy requires a URL"
            next
          elsif strategies.exclude?(strategy)
            odebug "#{strategy_name} strategy does not apply to this URL"
            next
          end
        end

        next if strategy.blank?

        strategy_data = begin
          strategy.find_versions(url, livecheck_regex, cask: cask, &livecheck_strategy_block)
        rescue ArgumentError => e
          raise unless e.message.include?("unknown keyword: cask")

          odisabled "`def self.find_versions` in `#{strategy}` without a `cask` parameter"
        end
        match_version_map = strategy_data[:matches]
        regex = strategy_data[:regex]
        messages = strategy_data[:messages]

        if messages.is_a?(Array) && match_version_map.blank?
          puts messages unless json
          next if i + 1 < urls.length

          return status_hash(formula_or_cask, "error", messages, full_name: full_name, verbose: verbose)
        end

        if debug
          puts "URL (strategy):   #{strategy_data[:url]}" if strategy_data[:url] != url
          puts "URL (final):      #{strategy_data[:final_url]}" if strategy_data[:final_url]
          puts "Regex (strategy): #{strategy_data[:regex].inspect}" if strategy_data[:regex] != livecheck_regex
          puts "Cached?:          Yes" if strategy_data[:cached] == true
        end

        match_version_map.delete_if do |_match, version|
          next true if version.blank?
          next false if has_livecheckable

          UNSTABLE_VERSION_KEYWORDS.any? do |rejection|
            version.to_s.include?(rejection)
          end
        end

        next if match_version_map.blank?

        if debug
          puts
          puts "Matched Versions:"

          if verbose
            match_version_map.each do |match, version|
              puts "#{match} => #{version.inspect}"
            end
          else
            puts match_version_map.values.join(", ")
          end
        end

        version_info = {
          latest: Version.new(match_version_map.values.max_by { |v| LivecheckVersion.create(formula_or_cask, v) }),
        }

        if json && verbose
          version_info[:meta] = {}

          if livecheck_references.present?
            version_info[:meta][:references] = livecheck_references.map do |ref_formula_or_cask|
              case ref_formula_or_cask
              when Formula
                { formula: formula_name(ref_formula_or_cask, full_name: full_name) }
              when Cask::Cask
                { cask: cask_name(ref_formula_or_cask, full_name: full_name) }
              end
            end
          end

          version_info[:meta][:url] = {}
          version_info[:meta][:url][:symbol] = livecheck_url if livecheck_url.is_a?(Symbol) && livecheck_url_string
          version_info[:meta][:url][:original] = original_url
          version_info[:meta][:url][:processed] = url if url != original_url
          version_info[:meta][:url][:strategy] = strategy_data[:url] if strategy_data[:url] != url
          version_info[:meta][:url][:final] = strategy_data[:final_url] if strategy_data[:final_url]

          version_info[:meta][:strategy] = strategy.present? ? strategy_name : nil
          version_info[:meta][:strategies] = strategies.map { |s| livecheck_strategy_names[s] } if strategies.present?
          version_info[:meta][:regex] = regex.inspect if regex.present?
          version_info[:meta][:cached] = true if strategy_data[:cached] == true
        end

        return version_info
      end
      # rubocop:enable Metrics/BlockLength

      nil
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
