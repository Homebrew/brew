# typed: true
# frozen_string_literal: true

require "livecheck/livecheck"

module Homebrew
  module Livecheck
    # The `Livecheck::SkipConditions` module primarily contains methods that
    # check for various formula/cask/resource conditions where a check should be skipped.
    #
    # @api private
    module SkipConditions
      module_function

      sig {
        params(
          package_or_resource: T.any(Formula, Cask::Cask, Resource),
          livecheckable:       T::Boolean,
          full_name:           T::Boolean,
          verbose:             T::Boolean,
        ).returns(Hash)
      }
      def package_or_resource_skip(package_or_resource, livecheckable, full_name: false, verbose: false)
        formula = package_or_resource if package_or_resource.is_a?(Formula)

        if (stable_url = formula&.stable&.url)
          stable_is_gist = stable_url.match?(%r{https?://gist\.github(?:usercontent)?\.com/}i)
          stable_from_google_code_archive = stable_url.match?(
            %r{https?://storage\.googleapis\.com/google-code-archive-downloads/}i,
          )
          stable_from_internet_archive = stable_url.match?(%r{https?://web\.archive\.org/}i)
        end

        skip_message = if package_or_resource.livecheck.skip_msg.present?
          package_or_resource.livecheck.skip_msg
        elsif !livecheckable
          if stable_from_google_code_archive
            "Stable URL is from Google Code Archive"
          elsif stable_from_internet_archive
            "Stable URL is from Internet Archive"
          elsif stable_is_gist
            "Stable URL is a GitHub Gist"
          end
        end

        return {} if !package_or_resource.livecheck.skip? && skip_message.blank?

        skip_messages = skip_message ? [skip_message] : nil
        Livecheck.status_hash(package_or_resource, "skipped", skip_messages, full_name: full_name, verbose: verbose)
      end

      sig {
        params(
          formula:        Formula,
          _livecheckable: T::Boolean,
          full_name:      T::Boolean,
          verbose:        T::Boolean,
        ).returns(Hash)
      }
      def formula_head_only(formula, _livecheckable, full_name: false, verbose: false)
        return {} if !formula.head_only? || formula.any_version_installed?

        Livecheck.status_hash(
          formula,
          "error",
          ["HEAD only formula must be installed to be livecheckable"],
          full_name: full_name,
          verbose:   verbose,
        )
      end

      sig {
        params(
          formula:       Formula,
          livecheckable: T::Boolean,
          full_name:     T::Boolean,
          verbose:       T::Boolean,
        ).returns(Hash)
      }
      def formula_deprecated(formula, livecheckable, full_name: false, verbose: false)
        return {} if !formula.deprecated? || livecheckable

        Livecheck.status_hash(formula, "deprecated", full_name: full_name, verbose: verbose)
      end

      sig {
        params(
          formula:       Formula,
          livecheckable: T::Boolean,
          full_name:     T::Boolean,
          verbose:       T::Boolean,
        ).returns(Hash)
      }
      def formula_disabled(formula, livecheckable, full_name: false, verbose: false)
        return {} if !formula.disabled? || livecheckable

        Livecheck.status_hash(formula, "disabled", full_name: full_name, verbose: verbose)
      end

      sig {
        params(
          formula:       Formula,
          livecheckable: T::Boolean,
          full_name:     T::Boolean,
          verbose:       T::Boolean,
        ).returns(Hash)
      }
      def formula_versioned(formula, livecheckable, full_name: false, verbose: false)
        return {} if !formula.versioned_formula? || livecheckable

        Livecheck.status_hash(formula, "versioned", full_name: full_name, verbose: verbose)
      end

      sig {
        params(
          cask:          Cask::Cask,
          livecheckable: T::Boolean,
          full_name:     T::Boolean,
          verbose:       T::Boolean,
        ).returns(Hash)
      }
      def cask_discontinued(cask, livecheckable, full_name: false, verbose: false)
        return {} if !cask.discontinued? || livecheckable

        Livecheck.status_hash(cask, "discontinued", full_name: full_name, verbose: verbose)
      end

      sig {
        params(
          cask:          Cask::Cask,
          livecheckable: T::Boolean,
          full_name:     T::Boolean,
          verbose:       T::Boolean,
        ).returns(Hash)
      }
      def cask_deprecated(cask, livecheckable, full_name: false, verbose: false)
        return {} if !cask.deprecated? || livecheckable

        Livecheck.status_hash(cask, "deprecated", full_name: full_name, verbose: verbose)
      end

      sig {
        params(
          cask:          Cask::Cask,
          livecheckable: T::Boolean,
          full_name:     T::Boolean,
          verbose:       T::Boolean,
        ).returns(Hash)
      }
      def cask_disabled(cask, livecheckable, full_name: false, verbose: false)
        return {} if !cask.disabled? || livecheckable

        Livecheck.status_hash(cask, "disabled", full_name: full_name, verbose: verbose)
      end

      sig {
        params(
          cask:          Cask::Cask,
          livecheckable: T::Boolean,
          full_name:     T::Boolean,
          verbose:       T::Boolean,
        ).returns(Hash)
      }
      def cask_version_latest(cask, livecheckable, full_name: false, verbose: false)
        return {} if !(cask.present? && cask.version&.latest?) || livecheckable

        Livecheck.status_hash(cask, "latest", full_name: full_name, verbose: verbose)
      end

      sig {
        params(
          cask:          Cask::Cask,
          livecheckable: T::Boolean,
          full_name:     T::Boolean,
          verbose:       T::Boolean,
        ).returns(Hash)
      }
      def cask_url_unversioned(cask, livecheckable, full_name: false, verbose: false)
        return {} if !(cask.present? && cask.url&.unversioned?) || livecheckable

        Livecheck.status_hash(cask, "unversioned", full_name: full_name, verbose: verbose)
      end

      # Skip conditions for formulae.
      FORMULA_CHECKS = [
        :package_or_resource_skip,
        :formula_head_only,
        :formula_deprecated,
        :formula_disabled,
        :formula_versioned,
      ].freeze

      # Skip conditions for casks.
      CASK_CHECKS = [
        :package_or_resource_skip,
        :cask_discontinued,
        :cask_deprecated,
        :cask_disabled,
        :cask_version_latest,
        :cask_url_unversioned,
      ].freeze

      # Skip conditions for resources.
      RESOURCE_CHECKS = [
        :package_or_resource_skip,
      ].freeze

      # If a formula/cask/resource should be skipped, we return a hash from
      # `Livecheck#status_hash`, which contains a `status` type and sometimes
      # error `messages`.
      sig {
        params(
          package_or_resource: T.any(Formula, Cask::Cask, Resource),
          full_name:           T::Boolean,
          verbose:             T::Boolean,
        ).returns(Hash)
      }
      def skip_information(package_or_resource, full_name: false, verbose: false)
        livecheckable = package_or_resource.livecheckable?

        checks = case package_or_resource
        when Formula
          FORMULA_CHECKS
        when Cask::Cask
          CASK_CHECKS
        when Resource
          RESOURCE_CHECKS
        end
        return {} unless checks

        checks.each do |method_name|
          skip_hash = send(method_name, package_or_resource, livecheckable, full_name: full_name, verbose: verbose)
          return skip_hash if skip_hash.present?
        end

        {}
      end

      # Skip conditions for formulae/casks/resources referenced in a `livecheck` block
      # are treated differently than normal. We only respect certain skip
      # conditions (returning the related hash) and others are treated as
      # errors.
      sig {
        params(
          livecheck_package_or_resource:     T.any(Formula, Cask::Cask, Resource),
          original_package_or_resource_name: String,
          full_name:                         T::Boolean,
          verbose:                           T::Boolean,
        ).returns(T.nilable(Hash))
      }
      def referenced_skip_information(
        livecheck_package_or_resource,
        original_package_or_resource_name,
        full_name: false,
        verbose: false
      )
        skip_info = SkipConditions.skip_information(
          livecheck_package_or_resource,
          full_name: full_name,
          verbose:   verbose,
        )
        return if skip_info.blank?

        referenced_name = Livecheck.package_or_resource_name(livecheck_package_or_resource, full_name: full_name)
        referenced_type = case livecheck_package_or_resource
        when Formula
          :formula
        when Cask::Cask
          :cask
        when Resource
          :resource
        end

        if skip_info[:status] != "error" &&
           !(skip_info[:status] == "skipped" && livecheck_package_or_resource.livecheck.skip?)
          error_msg_end = if skip_info[:status] == "skipped"
            "automatically skipped"
          else
            "skipped as #{skip_info[:status]}"
          end

          raise "Referenced #{referenced_type} (#{referenced_name}) is #{error_msg_end}"
        end

        skip_info[referenced_type] = original_package_or_resource_name
        skip_info
      end

      # Prints default livecheck output in relation to skip conditions.
      sig { params(skip_hash: Hash).void }
      def print_skip_information(skip_hash)
        return unless skip_hash.is_a?(Hash)

        name = if skip_hash[:formula].is_a?(String)
          skip_hash[:formula]
        elsif skip_hash[:cask].is_a?(String)
          skip_hash[:cask]
        elsif skip_hash[:resource].is_a?(String)
          "  #{skip_hash[:resource]}"
        end
        return unless name

        if skip_hash[:messages].is_a?(Array) && skip_hash[:messages].count.positive?
          # TODO: Handle multiple messages, only if needed in the future
          if skip_hash[:status] == "skipped"
            puts "#{Tty.red}#{name}#{Tty.reset}: skipped - #{skip_hash[:messages][0]}"
          else
            puts "#{Tty.red}#{name}#{Tty.reset}: #{skip_hash[:messages][0]}"
          end
        elsif skip_hash[:status].present?
          puts "#{Tty.red}#{name}#{Tty.reset}: #{skip_hash[:status]}"
        end
      end
    end
  end
end
