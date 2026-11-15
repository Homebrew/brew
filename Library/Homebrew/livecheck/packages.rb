# typed: strict
# frozen_string_literal: true

module Homebrew
  module Livecheck
    # Package names, references and URLs used by livecheck.
    module Packages
      extend T::Helpers

      requires_ancestor { T.class_of(Livecheck) }

      # Uses `formulae_and_casks_to_check` to identify taps in use other than
      # homebrew/core and homebrew/cask and loads strategies from them.
      sig { params(formulae_and_casks_to_check: T::Array[T.any(Formula, Cask::Cask)]).void }
      def load_other_tap_strategies(formulae_and_casks_to_check)
        other_taps = {}
        formulae_and_casks_to_check.each do |formula_or_cask|
          tap = formula_or_cask.tap
          next unless tap
          next if tap.core_tap?
          next if tap.core_cask_tap?
          next if other_taps[tap.name]

          other_taps[tap.name] = tap
        end
        other_taps = other_taps.sort.to_h

        other_taps.each_value do |tap|
          tap_strategy_path = "#{tap.path}/livecheck/strategy"
          Dir["#{tap_strategy_path}/*.rb"].each { require(it) } if Dir.exist?(tap_strategy_path)
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
        # Check the `livecheck` block for a formula or cask reference
        livecheck = formula_or_cask.livecheck
        livecheck_formula = livecheck.formula
        livecheck_cask = livecheck.cask
        return [nil, references] if livecheck_formula.blank? && livecheck_cask.blank?

        # Load the referenced formula or cask
        referenced_formula_or_cask = Homebrew::API.with_no_api_env do
          if livecheck_formula
            Formulary.factory(livecheck_formula)
          elsif livecheck_cask
            Cask::CaskLoader.load(livecheck_cask)
          else
            raise "livecheck formula or cask not found"
          end
        end

        # Error if a `livecheck` block references a formula/cask that was already
        # referenced (or itself)
        if referenced_formula_or_cask == first_formula_or_cask ||
           referenced_formula_or_cask == formula_or_cask ||
           references.include?(referenced_formula_or_cask)
          if debug
            # Print the chain of references for debugging
            puts "Reference Chain:"
            puts package_or_resource_name(first_formula_or_cask, full_name:)

            references << referenced_formula_or_cask
            references.each do |ref_formula_or_cask|
              puts package_or_resource_name(ref_formula_or_cask, full_name:)
            end
          end

          raise "Circular formula/cask reference encountered"
        end
        references << referenced_formula_or_cask

        # Check the referenced formula/cask for a reference
        next_referenced_formula_or_cask, next_references = resolve_livecheck_reference(
          referenced_formula_or_cask,
          first_formula_or_cask,
          references,
          full_name:,
          debug:,
        )

        # Returning references along with the final referenced formula/cask
        # allows us to print the chain of references in the debug output
        [
          next_referenced_formula_or_cask || referenced_formula_or_cask,
          next_references,
        ]
      end

      sig {
        params(packages: T::Array[T.any(Formula, Cask::Cask)], full_name: T::Boolean)
          .returns(T::Array[T.any(Formula, Cask::Cask)])
      }
      def ambiguous_packages(packages, full_name: false)
        packages.group_by { |item| package_or_resource_name(item, full_name:) }
                .values.select { |items| items.length > 1 }.flatten
      end
      private :ambiguous_packages

      sig { params(package_or_resource: T.any(Formula, Cask::Cask, Resource)).returns(T.nilable(Version)) }
      def current_version(package_or_resource)
        case package_or_resource
        when Formula
          if package_or_resource.head_only?
            commit = package_or_resource.any_installed_version&.version&.commit
            Version.new(commit) if commit
          else
            package_or_resource.stable&.version
          end
        when Cask::Cask
          Version.new(package_or_resource.version)
        when Resource
          package_or_resource.version
        else
          T.absurd(package_or_resource)
        end
      end

      sig { params(package_or_resource: T.any(Formula, Cask::Cask, Resource), full_name: T::Boolean).returns(String) }
      def package_or_resource_name(package_or_resource, full_name: false)
        case package_or_resource
        when Formula
          formula_name(package_or_resource, full_name:)
        when Cask::Cask
          cask_name(package_or_resource, full_name:)
        when Resource
          package_or_resource.name.to_s
        else
          T.absurd(package_or_resource)
        end
      end

      sig {
        params(
          livecheck_url:       T.any(String, Symbol),
          package_or_resource: T.any(Formula, Cask::Cask, Resource),
        ).returns(String)
      }
      def livecheck_url_to_string(livecheck_url, package_or_resource)
        livecheck_url_string = case livecheck_url
        when String
          livecheck_url
        when :url
          if package_or_resource.is_a?(Cask::Cask) || package_or_resource.is_a?(Resource)
            package_or_resource.url&.to_s
          end
        when :head
          package_or_resource.head&.url if package_or_resource.is_a?(Formula)
        when :stable
          package_or_resource.stable&.url if package_or_resource.is_a?(Formula)
        when :homepage
          package_or_resource.homepage unless package_or_resource.is_a?(Resource)
        end

        if livecheck_url.is_a?(Symbol) && !livecheck_url_string
          raise ArgumentError, "`url #{livecheck_url.inspect}` does not reference a checkable URL"
        end

        livecheck_url_string
      end

      # Returns an Array containing the formula/cask/resource URLs that can be used by livecheck.
      sig { params(package_or_resource: T.any(Formula, Cask::Cask, Resource)).returns(T::Array[String]) }
      def checkable_urls(package_or_resource)
        urls = []

        case package_or_resource
        when Formula
          if (stable = package_or_resource.stable)
            urls << stable.url
            urls.concat(stable.mirrors)
          end
          head = package_or_resource.head
          urls << head.url if head
          urls << package_or_resource.homepage if package_or_resource.homepage
        when Cask::Cask
          urls << package_or_resource.url.to_s if package_or_resource.url
          urls << package_or_resource.homepage if package_or_resource.homepage
        when Resource
          urls << package_or_resource.url
        else
          T.absurd(package_or_resource)
        end

        urls.compact.uniq
      end

      # livecheck should fetch a URL using brewed curl if the formula/cask
      # contains a `stable`/`url` or `head` URL `using: :homebrew_curl` that
      # shares the same host or uses it as a parent domain.
      sig { params(formula_or_cask: T.any(Formula, Cask::Cask), url: String).returns(T::Boolean) }
      def use_homebrew_curl?(formula_or_cask, url)
        host = url_host(url)
        return false unless host

        homebrew_curl_hosts = case formula_or_cask
        when Formula
          [formula_or_cask.stable, formula_or_cask.head].filter_map do |spec|
            next unless spec
            next if spec.using != :homebrew_curl
            next unless (spec_url = spec.url)

            url_host(spec_url)
          end
        when Cask::Cask
          cask_url = formula_or_cask.url
          return false if cask_url&.using != :homebrew_curl

          [url_host(cask_url.to_s)].compact
        end

        homebrew_curl_hosts.any? do |homebrew_curl_host|
          host == homebrew_curl_host ||
            host.end_with?(".#{homebrew_curl_host}") ||
            homebrew_curl_host.end_with?(".#{host}")
        end
      end

      private

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

      sig { params(url: String).returns(T.nilable(String)) }
      def url_host(url)
        URI.parse(url).host&.downcase
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
