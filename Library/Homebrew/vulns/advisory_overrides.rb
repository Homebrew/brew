# typed: strict
# frozen_string_literal: true

require "vulns/identify"
require "yaml"

module Homebrew
  module Vulns
    # Reviewed formula identity and candidate-specific corrections for advisory
    # matching. These are intentionally keyed by formula, and range corrections
    # are further keyed by upstream advisory identifier, so a bad upstream range
    # cannot silently change unrelated matches.
    class AdvisoryOverrides
      class Error < RuntimeError; end

      class RegistryPackageOverride < T::Struct
        const :ecosystem, String
        const :name, String
      end

      class Entry < T::Struct
        const :state, T.nilable(Symbol)
        const :fixed_in, T.nilable(String)
        const :fixed_in_overridden, T::Boolean
      end

      VALID_STATES = [:affected, :fixed, :not_applicable].freeze
      private_constant :VALID_STATES

      REGISTRY_PACKAGE_KEYS = %w[ecosystem name].freeze
      private_constant :REGISTRY_PACKAGE_KEYS

      sig { params(path: Pathname).returns(AdvisoryOverrides) }
      def self.from_file(path)
        new(YAML.safe_load(path.read, permitted_classes: [], permitted_symbols: [], aliases: false))
      rescue Psych::Exception => e
        raise Error, "Failed to parse advisory overrides at #{path}: #{e.message}"
      end

      # Keep formula and advisory entry validation, including the effective
      # override requirement, in sync with advisory-database spec/overrides_spec.rb.
      sig { params(data: T.untyped).void }
      def initialize(data)
        @skipped_formulae = T.let({}, T::Hash[String, T::Boolean])
        @registry_packages = T.let({}, T::Hash[String, RegistryPackageOverride])
        @advisories = T.let({}, T::Hash[String, T::Hash[String, Entry]])
        @preserved_homebrew_ranges = T.let({}, T::Hash[String, T::Array[String]])

        root = hash(data, "top level")
        root.each do |formula_name, raw_formula|
          raise Error, "Formula names must be strings" unless formula_name.is_a?(String)

          formula = hash(raw_formula, formula_name)
          reject_unknown_keys(formula, %w[skip advisories registry_package], formula_name)

          skip = formula.fetch("skip", false)
          raise Error, "#{formula_name}.skip must be true or false" unless [true, false].include?(skip)

          @skipped_formulae[formula_name] = true if skip

          if formula.key?("registry_package")
            location = "#{formula_name}.registry_package"
            package = hash(formula.fetch("registry_package"), location)
            reject_unknown_keys(package, REGISTRY_PACKAGE_KEYS, location)
            missing = REGISTRY_PACKAGE_KEYS - package.keys
            raise Error, "#{location} is missing key(s): #{missing.join(", ")}" if missing.any?

            ecosystem = nonblank_string(package.fetch("ecosystem"), "#{location}.ecosystem")
            name = nonblank_string(package.fetch("name"), "#{location}.name")
            unless Identify.registry_package_for(ecosystem:, name:)
              raise Error, "#{location} must identify a supported registry package with a canonical OSV name"
            end

            @registry_packages[formula_name] = RegistryPackageOverride.new(ecosystem:, name:)
          end
          next unless formula.key?("advisories")

          raw_advisories = hash(formula.fetch("advisories"), "#{formula_name}.advisories")
          parsed = T.let({}, T::Hash[String, Entry])
          raw_advisories.each do |identifier, raw_entry|
            raise Error, "#{formula_name} advisory identifiers must be strings" unless identifier.is_a?(String)

            entry = hash(raw_entry, "#{formula_name}.advisories.#{identifier}")
            reject_unknown_keys(entry, %w[range_state upstream_fixed_in preserve_homebrew_ranges],
                                "#{formula_name}.advisories.#{identifier}")

            preserve_ranges = entry.fetch("preserve_homebrew_ranges", false)
            unless [true, false].include?(preserve_ranges)
              raise Error, "#{formula_name}.advisories.#{identifier}.preserve_homebrew_ranges must be true or false"
            end

            (@preserved_homebrew_ranges[formula_name] ||= []) << identifier if preserve_ranges

            state = T.let(nil, T.nilable(Symbol))
            if entry.key?("range_state")
              raw_state = entry.fetch("range_state")
              state = raw_state.to_sym if raw_state.is_a?(String)
              if state.nil? || VALID_STATES.exclude?(state)
                raise Error, "#{formula_name}.advisories.#{identifier}.range_state must be " \
                             "affected, fixed, or not_applicable"
              end
            end

            fixed_in_overridden = entry.key?("upstream_fixed_in")
            fixed_in = entry["upstream_fixed_in"]
            if !fixed_in.nil? && !fixed_in.is_a?(String)
              raise Error, "#{formula_name}.advisories.#{identifier}.upstream_fixed_in must be a string or null"
            end
            if state.nil? && !fixed_in_overridden && !preserve_ranges
              raise Error, "#{formula_name}.advisories.#{identifier} must override at least one field"
            end

            if state || fixed_in_overridden
              parsed[identifier] = Entry.new(state:, fixed_in:, fixed_in_overridden:)
            end
          end
          @advisories[formula_name] = parsed.freeze
        end
        @skipped_formulae.freeze
        @registry_packages.freeze
        @advisories.freeze
        @preserved_homebrew_ranges.each_value(&:freeze)
        @preserved_homebrew_ranges.freeze
      end

      sig { params(formula_name: String).returns(T::Boolean) }
      def skip_formula?(formula_name)
        @skipped_formulae.key?(formula_name)
      end

      sig { params(formula_name: String).returns(T.nilable(RegistryPackageOverride)) }
      def registry_package_override(formula_name)
        @registry_packages[formula_name]
      end

      sig { params(formula_name: String, identifiers: T::Array[String]).returns(T.nilable(Entry)) }
      def advisory_override(formula_name, identifiers)
        formula = @advisories[formula_name]
        return unless formula

        identifiers.each do |identifier|
          override = formula[identifier]
          return override if override
        end
        nil
      end

      # A protection under any alias applies to the whole family, independently
      # of whichever alias supplies the upstream state or version override.
      sig { params(formula_name: String, identifiers: T::Array[String]).returns(T::Boolean) }
      def preserve_homebrew_ranges?(formula_name, identifiers)
        @preserved_homebrew_ranges.fetch(formula_name, []).intersect?(identifiers)
      end

      private

      sig { params(value: T.untyped, location: String).returns(T::Hash[T.untyped, T.untyped]) }
      def hash(value, location)
        return value if value.is_a?(Hash)

        raise Error, "#{location} must be a mapping"
      end

      sig { params(value: T.anything, location: String).returns(String) }
      def nonblank_string(value, location)
        case value
        when String
          return value if value.match?(/\S/)
        end

        raise Error, "#{location} must be a non-blank string"
      end

      sig {
        params(value: T::Hash[T.untyped, T.untyped], allowed: T::Array[String], location: String).void
      }
      def reject_unknown_keys(value, allowed, location)
        unknown = value.keys - allowed
        return if unknown.empty?

        raise Error, "#{location} has unknown key(s): #{unknown.join(", ")}"
      end
    end
  end
end
