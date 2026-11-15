# typed: strict
# frozen_string_literal: true

require "api/env"
require "livecheck/constants"
require "livecheck/error"
require "livecheck/progress"
require "livecheck/packages"
require "livecheck/output"
require "livecheck/throttle"
require "livecheck/livecheck_version"
require "livecheck/skip_conditions"
require "livecheck/strategy"
require "formula_versions"
require "uri"
require "utils/git"
require "utils/output"

module Homebrew
  # The {Livecheck} module consists of methods used by the `brew livecheck`
  # command. These methods print the requested livecheck information
  # for formulae.
  module Livecheck
    extend Utils::Output::Mixin
    extend Packages
    extend Output
    extend Throttle

    NO_CURRENT_VERSION_MSG = "Unable to identify current version"
    NO_VERSIONS_MSG = "Unable to get versions"

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
    private_constant :UNSTABLE_VERSION_KEYWORDS

    sig { params(strategy_class: T::Class[Strategic]).returns(String) }
    def self.livecheck_strategy_names(strategy_class)
      @livecheck_strategy_names ||= T.let({}, T.nilable(T::Hash[T::Class[Strategic], String]))
      @livecheck_strategy_names[strategy_class] ||= Utils.demodulize(strategy_class.name)
    end

    sig { params(strategy_class: T::Class[Strategic]).returns(T::Array[Symbol]) }
    def self.livecheck_find_versions_parameters(strategy_class)
      @livecheck_find_versions_parameters ||= T.let({}, T.nilable(T::Hash[T::Class[Strategic], T::Array[Symbol]]))
      @livecheck_find_versions_parameters[strategy_class] ||=
        (T::Utils.signature_for_method(strategy_class.method(:find_versions))&.parameters ||
         strategy_class.method(:find_versions).parameters).map(&:second)
    end

    # Executes the livecheck logic for each formula/cask in the
    # `formulae_and_casks_to_check` array and prints the results.
    sig {
      params(
        formulae_and_casks_to_check: T::Array[T.any(Formula, Cask::Cask)],
        full_name:                   T::Boolean,
        handle_name_conflict:        T::Boolean,
        check_resources:             T::Boolean,
        json:                        T::Boolean,
        newer_only:                  T::Boolean,
        extract_plist:               T::Boolean,
        debug:                       T::Boolean,
        quiet:                       T::Boolean,
        verbose:                     T::Boolean,
      ).void
    }
    def self.run_checks(
      formulae_and_casks_to_check,
      full_name: false, handle_name_conflict: false, check_resources: false, json: false, newer_only: false,
      extract_plist: false, debug: false, quiet: false, verbose: false
    )
      load_other_tap_strategies(formulae_and_casks_to_check)

      ambiguous_casks = if handle_name_conflict
        ambiguous_packages(formulae_and_casks_to_check, full_name: true).grep(Cask::Cask)
      else
        []
      end
      ambiguous_names = full_name ? [] : ambiguous_packages(formulae_and_casks_to_check - ambiguous_casks)

      has_a_newer_upstream_version = T.let(false, T::Boolean)

      formulae_and_casks_total = formulae_and_casks_to_check.count
      progress = Progress.new(total: formulae_and_casks_total, enabled: json && !quiet && $stderr.tty?)

      # Allow ExtractPlist strategy if only one formula/cask is being checked.
      extract_plist = true if formulae_and_casks_total == 1

      formulae_checked = formulae_and_casks_to_check.map.with_index do |formula_or_cask, i|
        formula = formula_or_cask if formula_or_cask.is_a?(Formula)
        cask = formula_or_cask if formula_or_cask.is_a?(Cask::Cask)
        formula.head&.downloader&.quiet! if formula

        use_full_name = full_name || ambiguous_names.include?(formula_or_cask)
        name = package_or_resource_name(formula_or_cask, full_name: use_full_name)

        referenced_formula_or_cask, livecheck_references =
          resolve_livecheck_reference(formula_or_cask, full_name: use_full_name, debug:)

        puts(i.positive? ? "\n----------\n\n" : "") if debug

        # Check skip conditions for a referenced formula/cask
        if referenced_formula_or_cask
          skip_info = SkipConditions.referenced_skip_information(
            referenced_formula_or_cask,
            name,
            full_name:     use_full_name,
            verbose:,
            extract_plist:,
          )
        end

        skip_info ||= SkipConditions.skip_information(
          formula_or_cask,
          full_name:     use_full_name,
          verbose:,
          extract_plist:,
        )
        if skip_info.present?
          next skip_info if json && !newer_only

          SkipConditions.print_skip_information(skip_info) if !newer_only && !quiet
          next
        end

        # Use the `stable` version for comparison except for installed
        # HEAD-only formulae. A formula with `stable` and `head` that's
        # installed using `--head` will still use the `stable` version for
        # comparison.
        current = current_version(formula_or_cask)
        unless current
          raise Livecheck::Error, NO_CURRENT_VERSION_MSG unless json
          next if quiet

          next status_hash(formula_or_cask, "error", [NO_CURRENT_VERSION_MSG], full_name: use_full_name, verbose:)
        end

        current_str = current.to_s
        current = LivecheckVersion.create(formula_or_cask, current)

        latest = if formula&.head_only? && (head = formula.head)
          Version.new(head.downloader.fetch_last_commit)
        else
          version_info = latest_version(
            formula_or_cask,
            referenced_formula_or_cask:,
            livecheck_references:,
            json:, full_name: use_full_name, verbose:, debug:
          )
          version_info[:latest] if version_info.present?
        end

        check_for_resources = check_resources && formula_or_cask.is_a?(Formula) && formula_or_cask.resources.present?
        if check_for_resources
          resource_version_info = formula_or_cask.resources.map do |resource|
            res_skip_info ||= SkipConditions.skip_information(resource, verbose:)
            if res_skip_info.present?
              res_skip_info
            else
              res_version_info = resource_version(
                resource,
                latest.to_s,
                json:,
                full_name: use_full_name,
                debug:,
                quiet:,
                verbose:,
              )
              if res_version_info.empty?
                status_hash(resource, "error", [NO_VERSIONS_MSG], verbose:)
              else
                res_version_info
              end
            end
          end.compact_blank
          Homebrew.failed = true if resource_version_info.any? { |info| info[:status] == "error" }
        end

        if latest.blank?
          raise Livecheck::Error, NO_VERSIONS_MSG unless json
          next if quiet

          next version_info if version_info.is_a?(Hash) && version_info[:status] && version_info[:messages]

          latest_info = status_hash(formula_or_cask, "error", [NO_VERSIONS_MSG], full_name: use_full_name,
                                                                                 verbose:)
          if check_for_resources
            unless verbose
              resource_version_info.map! do |info|
                info.delete(:meta)
                info
              end
            end
            latest_info[:resources] = resource_version_info
          end

          next latest_info
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
          latest_throttled:    version_info&.dig(:latest_throttled),
          outdated:            is_outdated,
          newer_than_upstream: is_newer_than_upstream,
        }.compact
        info[:meta] = {
          livecheck_defined: formula_or_cask.livecheck_defined?,
        }
        info[:meta][:head_only] = true if formula&.head_only?
        info[:meta].merge!(version_info[:meta]) if version_info.present? && version_info.key?(:meta)

        info[:resources] = resource_version_info if check_for_resources

        next if newer_only && !info[:version][:outdated]

        has_a_newer_upstream_version ||= true

        if json
          progress.increment
          info.delete(:meta) unless verbose
          if check_for_resources && !verbose
            resource_version_info.map! do |resource_info|
              resource_info.delete(:meta)
              resource_info
            end
          end
          next info
        end
        puts if debug
        print_latest_version(info, verbose:, ambiguous_cask: ambiguous_casks.include?(formula_or_cask))
        print_resources_info(resource_version_info, verbose:) if check_for_resources
        nil
      rescue => e
        Homebrew.failed = true
        use_full_name = full_name || ambiguous_names.include?(formula_or_cask)

        if json
          progress.increment
          unless quiet
            status_hash(formula_or_cask, "error", [e.to_s], full_name: use_full_name,
                                                            verbose:)
          end
        elsif !quiet
          name = package_or_resource_name(formula_or_cask, full_name: use_full_name)
          name += " (cask)" if ambiguous_casks.include?(formula_or_cask)

          onoe "#{Tty.blue}#{name}#{Tty.reset}: #{e}"
          if debug && !e.is_a?(Livecheck::Error)
            require "utils/backtrace"
            $stderr.puts Utils::Backtrace.clean(e)
          end
          print_resources_info(resource_version_info, verbose:) if check_for_resources
          nil
        end
      end

      puts "No newer upstream versions." if newer_only && !has_a_newer_upstream_version && !debug && !json && !quiet

      return unless json

      progress.finish

      puts JSON.pretty_generate(formulae_checked.compact)
    end

    # Identifies the latest version of the formula/cask and returns a Hash containing
    # the version information. Returns nil if a latest version couldn't be found.
    sig {
      params(
        formula_or_cask:            T.any(Formula, Cask::Cask),
        referenced_formula_or_cask: T.nilable(T.any(Formula, Cask::Cask)),
        livecheck_references:       T::Array[T.any(Formula, Cask::Cask)],
        json:                       T::Boolean,
        full_name:                  T::Boolean,
        verbose:                    T::Boolean,
        debug:                      T::Boolean,
      ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
    }
    def self.latest_version(
      formula_or_cask,
      referenced_formula_or_cask: nil,
      livecheck_references: [],
      json: false, full_name: false, verbose: false, debug: false
    )
      formula = formula_or_cask if formula_or_cask.is_a?(Formula)
      cask = formula_or_cask if formula_or_cask.is_a?(Cask::Cask)

      livecheck_defined = formula_or_cask.livecheck_defined?
      livecheck = formula_or_cask.livecheck
      referenced_livecheck = referenced_formula_or_cask&.livecheck

      livecheck_options = referenced_livecheck&.options&.merge(livecheck.options) || livecheck.options.deep_dup
      livecheck_url_options = livecheck_options.url_options.compact
      livecheck_url = livecheck.url || referenced_livecheck&.url
      livecheck_regex = livecheck.regex || referenced_livecheck&.regex
      livecheck_strategy = livecheck.strategy || referenced_livecheck&.strategy
      livecheck_strategy_block = livecheck.strategy_block || referenced_livecheck&.strategy_block
      livecheck_throttle = livecheck.throttle || referenced_livecheck&.throttle
      livecheck_throttle_days = livecheck.throttle_days || referenced_livecheck&.throttle_days

      referenced_package = referenced_formula_or_cask || formula_or_cask

      livecheck_url_string = livecheck_url_to_string(livecheck_url, referenced_package) if livecheck_url

      urls = [livecheck_url_string] if livecheck_url_string
      urls ||= checkable_urls(referenced_package)

      if debug
        if formula
          puts "Formula:          #{formula_name(formula, full_name:)}"
          puts "Head only?:       true" if formula.head_only?
        elsif cask
          puts "Cask:             #{cask_name(formula_or_cask, full_name:)}"
        end
        puts "livecheck block?: #{livecheck_defined ? "Yes" : "No"}"
        if livecheck_throttle || livecheck_throttle_days
          throttle_items = []
          if livecheck_throttle
            throttle_items << "#{livecheck_throttle} #{Utils.pluralize("version", livecheck_throttle)}"
          end
          if livecheck_throttle_days
            throttle_items << "#{livecheck_throttle_days} #{Utils.pluralize("day", livecheck_throttle_days)}"
          end
          puts "Throttle:         #{throttle_items.join(" or ")}"
        end

        livecheck_references.each do |ref_formula_or_cask|
          case ref_formula_or_cask
          when Formula
            puts "Formula Ref:      #{formula_name(ref_formula_or_cask, full_name:)}"
          when Cask::Cask
            puts "Cask Ref:         #{cask_name(ref_formula_or_cask, full_name:)}"
          else
            T.absurd(ref_formula_or_cask) # simplecov:disable
          end
        end
      end

      checked_urls = []
      urls.each_with_index do |original_url, i|
        url = original_url
        next if checked_urls.include?(url)

        strategies = Strategy.from_url(
          url,
          livecheck_strategy:,
          regex_provided:     livecheck_regex.present?,
          block_provided:     livecheck_strategy_block.present?,
        )
        strategy = Strategy.from_symbol(livecheck_strategy) || strategies.first
        next unless strategy

        strategy_name = livecheck_strategy_names(strategy)

        if strategy.respond_to?(:preprocess_url)
          url = strategy.preprocess_url(url)
          next if checked_urls.include?(url)
        end

        if debug
          print_strategy_info(original_url:, url:, url_spec: livecheck_url, url_options: livecheck_url_options,
                              strategies:, strategy:, regex: livecheck_regex, verbose:)
        end

        if livecheck_strategy.present?
          if livecheck_url.blank? && strategy.method(:find_versions).parameters.include?([:keyreq, :url])
            odebug "#{strategy_name} strategy requires a URL"
            next
          elsif livecheck_strategy != :page_match && strategies.exclude?(strategy)
            odebug "#{strategy_name} strategy does not apply to this URL"
            next
          end
        end

        next if strategy.blank?

        if (livecheck_homebrew_curl = livecheck_options.homebrew_curl).nil?
          case strategy_name
          when "PageMatch", "HeaderMatch"
            if (homebrew_curl = use_homebrew_curl?(referenced_package, url))
              livecheck_options.homebrew_curl = homebrew_curl
              livecheck_homebrew_curl = homebrew_curl
            end
          end
        end
        puts "Homebrew curl?:   #{livecheck_homebrew_curl ? "Yes" : "No"}" if debug && !livecheck_homebrew_curl.nil?

        # Only use arguments that the strategy's `#find_versions` method
        # supports
        find_versions_parameters = livecheck_find_versions_parameters(strategy)
        strategy_args = {}
        strategy_args[:cask] = cask if find_versions_parameters.include?(:cask)
        strategy_args[:url] = url if find_versions_parameters.include?(:url)
        strategy_args[:regex] = livecheck_regex if find_versions_parameters.include?(:regex)
        strategy_args[:options] = livecheck_options if find_versions_parameters.include?(:options)
        strategy_args.compact!

        strategy_data = strategy.find_versions(**strategy_args, &livecheck_strategy_block)
        match_version_map = strategy_data[:matches]
        regex = strategy_data[:regex]
        messages = strategy_data[:messages]
        checked_urls << url

        if messages.is_a?(Array) && match_version_map.blank?
          puts messages unless json
          next if i + 1 < urls.length

          return status_hash(formula_or_cask, "error", messages, full_name:, verbose:)
        end

        if debug
          print_strategy_result(url:, regex: livecheck_regex, strategy_url: strategy_data[:url],
                                final_url: strategy_data[:final_url], strategy_regex: strategy_data[:regex],
                                cached: strategy_data[:cached])
        end

        filter_unstable_versions!(match_version_map, livecheck_defined:)
        next if match_version_map.blank?

        print_matches(match_version_map, verbose:) if debug

        version_info = {
          latest: Version.new(match_version_map.values.max_by { |v| LivecheckVersion.create(formula_or_cask, v) }),
        }

        if livecheck_throttle || livecheck_throttle_days
          version_info[:latest_throttled] = throttled_version(
            formula_or_cask, match_version_map, version_info[:latest],
            throttle_rate: livecheck_throttle, throttle_days: livecheck_throttle_days, debug:, verbose:
          )
        end

        if json && verbose
          version_info[:meta] = {}

          if livecheck_references.present?
            version_info[:meta][:references] = livecheck_references.map do |ref_formula_or_cask|
              case ref_formula_or_cask
              when Formula
                { formula: formula_name(ref_formula_or_cask, full_name:) }
              when Cask::Cask
                { cask: cask_name(ref_formula_or_cask, full_name:) }
              else
                T.absurd(ref_formula_or_cask) # simplecov:disable
              end
            end
          end

          if url != "None"
            version_info[:meta][:url] = {}
            version_info[:meta][:url][:symbol] = livecheck_url if livecheck_url.is_a?(Symbol) && livecheck_url_string
            version_info[:meta][:url][:original] = original_url
            version_info[:meta][:url][:processed] = url if url != original_url
            if strategy_data[:url].present? && strategy_data[:url] != url
              version_info[:meta][:url][:strategy] = strategy_data[:url]
            end
            version_info[:meta][:url][:final] = strategy_data[:final_url] if strategy_data[:final_url]
            version_info[:meta][:url][:options] = livecheck_url_options if livecheck_url_options.present?
          end
          version_info[:meta][:strategy] = strategy_name if strategy.present?
          version_info[:meta][:strategies] = strategies.map { |s| livecheck_strategy_names(s) } if strategies.present?
          version_info[:meta][:regex] = regex.inspect if regex.present?
          version_info[:meta][:cached] = true if strategy_data[:cached] == true
          version_info[:meta][:throttle] = livecheck_throttle if livecheck_throttle
          version_info[:meta][:throttle_days] = livecheck_throttle_days if livecheck_throttle_days

          version_info[:content] = strategy_data[:content] if strategy_data[:content] && strategy_name == "Pypi"
        end

        return version_info
      end
      nil
    end

    sig { params(matches: T::Hash[String, T.nilable(Version)], livecheck_defined: T::Boolean).void }
    def self.filter_unstable_versions!(matches, livecheck_defined:)
      matches.delete_if do |_match, version|
        next true if version.blank?
        next false if livecheck_defined

        UNSTABLE_VERSION_KEYWORDS.any? { |rejection| version.to_s.include?(rejection) }
      end
    end
    private_class_method :filter_unstable_versions!

    # Identifies the latest version of a resource and returns a Hash containing the
    # version information. Returns nil if a latest version couldn't be found.
    sig {
      params(
        resource:       Resource,
        formula_latest: String,
        json:           T::Boolean,
        full_name:      T::Boolean,
        debug:          T::Boolean,
        quiet:          T::Boolean,
        verbose:        T::Boolean,
      ).returns(T::Hash[Symbol, T.untyped])
    }
    def self.resource_version(
      resource,
      formula_latest,
      json: false,
      full_name: false,
      debug: false,
      quiet: false,
      verbose: false
    )
      livecheck_defined = resource.livecheck_defined?

      if debug
        puts "\n\n"
        puts "Resource:         #{resource.name}"
        puts "livecheck block?: #{livecheck_defined ? "Yes" : "No"}"
      end

      resource_version_info = {}

      livecheck = resource.livecheck
      livecheck_options = livecheck.options.deep_dup
      livecheck_url_options = livecheck_options.url_options.compact
      livecheck_reference = livecheck.formula
      livecheck_url = livecheck.url
      livecheck_regex = livecheck.regex
      livecheck_strategy = livecheck.strategy
      livecheck_strategy_block = livecheck.strategy_block

      livecheck_url_string = livecheck_url_to_string(livecheck_url, resource) if livecheck_url

      urls = [livecheck_url_string] if livecheck_url_string
      urls = ["None"] if livecheck_reference == :parent
      urls ||= checkable_urls(resource)

      checked_urls = []
      urls.each_with_index do |original_url, i|
        url = original_url.gsub(Constants::LATEST_VERSION, formula_latest)
        next if checked_urls.include?(url)

        strategies = Strategy.from_url(
          url,
          livecheck_strategy:,
          regex_provided:     livecheck_regex.present?,
          block_provided:     livecheck_strategy_block.present?,
        )
        strategy = Strategy.from_symbol(livecheck_strategy) || strategies.first
        next if strategy.blank? && livecheck_reference != :parent

        strategy_name = livecheck_strategy_names(strategy) if strategy.present?

        if strategy.respond_to?(:preprocess_url)
          url = strategy.preprocess_url(url)
          next if checked_urls.include?(url)
        end

        if debug
          print_strategy_info(original_url:, url:, url_spec: livecheck_url, url_options: livecheck_url_options,
                              strategies:, strategy:, regex: livecheck_regex, verbose:)
          if livecheck_reference == :parent
            resource_owner = resource.owner
            raise "Resource owner is nil" if resource_owner.nil?

            formula = full_name ? T.cast(resource_owner, ::Formula).full_name : resource_owner.name
            puts "Formula Ref:      #{formula} (parent)"
          end
        end

        if livecheck_strategy.present?
          if livecheck_url.blank? && strategy.method(:find_versions).parameters.include?([:keyreq, :url])
            odebug "#{strategy_name} strategy requires a URL"
            next
          elsif livecheck_strategy != :page_match && strategies.exclude?(strategy)
            odebug "#{strategy_name} strategy does not apply to this URL"
            next
          end
        end
        puts if debug && strategy.blank? && livecheck_reference != :parent
        next if strategy.blank? && livecheck_reference != :parent

        if debug && !(livecheck_homebrew_curl = livecheck_options.homebrew_curl).nil?
          puts "Homebrew curl?:   #{livecheck_homebrew_curl ? "Yes" : "No"}"
        end

        if livecheck_reference == :parent
          match_version_map = { formula_latest => Version.new(formula_latest) }
          cached = true
        else
          # Only use arguments that the strategy's `#find_versions` method
          # supports
          find_versions_parameters = livecheck_find_versions_parameters(strategy)
          strategy_args = {}
          strategy_args[:url] = url if find_versions_parameters.include?(:url)
          strategy_args[:regex] = livecheck_regex if find_versions_parameters.include?(:regex)
          strategy_args[:options] = livecheck_options if find_versions_parameters.include?(:options)
          strategy_args.compact!

          strategy_data = strategy.find_versions(**strategy_args, &livecheck_strategy_block)
          match_version_map = strategy_data[:matches]
          regex = strategy_data[:regex]
          messages = strategy_data[:messages]
          cached = strategy_data[:cached]
        end

        checked_urls << url

        if messages.is_a?(Array) && match_version_map.blank?
          puts messages unless json
          next if i + 1 < urls.length

          return status_hash(resource, "error", messages, verbose:)
        end

        if debug
          print_strategy_result(url:, regex: livecheck_regex, strategy_url: strategy_data&.dig(:url),
                                final_url: strategy_data&.dig(:final_url), strategy_regex: strategy_data&.dig(:regex),
                                cached:)
        end

        filter_unstable_versions!(match_version_map, livecheck_defined:)
        next if match_version_map.blank?

        print_matches(match_version_map, verbose:) if debug

        res_current = current_version(resource)
        return status_hash(resource, "error", [NO_CURRENT_VERSION_MSG], verbose:) if res_current.nil?

        res_latest = Version.new(match_version_map.values.max_by { |v| LivecheckVersion.create(resource, v) })

        return status_hash(resource, "error", [NO_VERSIONS_MSG], verbose:) if res_latest.blank?

        is_outdated = res_current < res_latest
        is_newer_than_upstream = res_current > res_latest

        resource_version_info = {
          resource: resource.name,
          version:  {
            current:             res_current.to_s,
            latest:              res_latest.to_s,
            outdated:            is_outdated,
            newer_than_upstream: is_newer_than_upstream,
          },
        }

        resource_version_info[:meta] = {
          livecheck_defined: livecheck_defined,
        }
        if livecheck_reference == :parent
          resource_owner = resource.owner
          raise "Resource owner is nil" if resource_owner.nil?

          formula = full_name ? T.cast(resource_owner, ::Formula).full_name : resource_owner.name
          resource_version_info[:meta][:references] =
            [{ formula:, symbol: :parent }]
        end
        if url != "None"
          resource_version_info[:meta][:url] = {}
          if livecheck_url.is_a?(Symbol) && livecheck_url_string
            resource_version_info[:meta][:url][:symbol] = livecheck_url
          end
          resource_version_info[:meta][:url][:original] = original_url
          resource_version_info[:meta][:url][:processed] = url if url != original_url
          if strategy_data&.dig(:url).present? && strategy_data[:url] != url
            resource_version_info[:meta][:url][:strategy] = strategy_data[:url]
          end
          resource_version_info[:meta][:url][:final] = strategy_data[:final_url] if strategy_data&.dig(:final_url)
          resource_version_info[:meta][:url][:options] = livecheck_url_options if livecheck_url_options.present?
        end
        resource_version_info[:meta][:strategy] = strategy_name if strategy.present?
        if strategies.present?
          resource_version_info[:meta][:strategies] = strategies.map { |s| livecheck_strategy_names(s) }
        end
        resource_version_info[:meta][:regex] = regex.inspect if regex.present?
        resource_version_info[:meta][:cached] = true if cached == true
      rescue => e
        Homebrew.failed = true
        if json
          status_hash(resource, "error", [e.to_s], verbose:)
        elsif !quiet
          onoe "#{Tty.blue}#{resource.name}#{Tty.reset}: #{e}"
          if debug && !e.is_a?(Livecheck::Error)
            require "utils/backtrace"
            $stderr.puts Utils::Backtrace.clean(e)
          end
          nil
        end
      end
      resource_version_info
    end
  end
end
