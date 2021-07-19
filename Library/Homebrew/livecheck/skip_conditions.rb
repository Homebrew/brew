# typed: true
# frozen_string_literal: true

require "livecheck/livecheck"

module Homebrew
  module Livecheck
    # The `Livecheck::SkipConditions` module primarily contains methods that
    # check for various formula/cask conditions where a check should be skipped.
    #
    # @api private
    module SkipConditions
      extend T::Sig

      module_function

      sig {
        params(
          formula_or_cask: T.any(Formula, Cask::Cask),
          livecheckable:   T::Boolean,
          full_name:       T::Boolean,
          verbose:         T::Boolean,
        ).returns(Hash)
      }
      def formula_or_cask_skip(formula_or_cask, livecheckable, full_name: false, verbose: false)
        formula = formula_or_cask if formula_or_cask.is_a?(Formula)

        if (stable_url = formula&.stable&.url)
          stable_is_gist = stable_url.match?(%r{https?://gist\.github(?:usercontent)?\.com/}i)
          stable_from_google_code_archive = stable_url.match?(
            %r{https?://storage\.googleapis\.com/google-code-archive-downloads/}i,
          )
          stable_from_internet_archive = stable_url.match?(%r{https?://web\.archive\.org/}i)
        end

        skip_message = if formula_or_cask.livecheck.skip_msg.present?
          formula_or_cask.livecheck.skip_msg
        elsif !livecheckable
          if stable_from_google_code_archive
            "Stable URL is from Google Code Archive"
          elsif stable_from_internet_archive
            "Stable URL is from Internet Archive"
          elsif stable_is_gist
            "Stable URL is a GitHub Gist"
          end
        end

        return {} if !formula_or_cask.livecheck.skip? && skip_message.blank?

        skip_messages = skip_message ? [skip_message] : nil
        Livecheck.status_hash(formula_or_cask, "skipped", skip_messages, full_name: full_name, verbose: verbose)
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
        :formula_or_cask_skip,
        :formula_head_only,
        :formula_deprecated,
        :formula_disabled,
        :formula_versioned,
      ].freeze

      # Skip conditions for casks.
      CASK_CHECKS = [
        :formula_or_cask_skip,
        :cask_discontinued,
        :cask_version_latest,
        :cask_url_unversioned,
      ].freeze

      # If a formula/cask should be skipped, we return a hash from
      # `Livecheck#status_hash`, which contains a `status` type and sometimes
      # error `messages`.
      sig {
        params(
          formula_or_cask: T.any(Formula, Cask::Cask),
          full_name:       T::Boolean,
          verbose:         T::Boolean,
        ).returns(Hash)
      }
      def skip_information(formula_or_cask, full_name: false, verbose: false)
        livecheckable = formula_or_cask.livecheckable?

        checks = case formula_or_cask
        when Formula
          FORMULA_CHECKS
        when Cask::Cask
          CASK_CHECKS
        end
        return {} unless checks

        checks.each do |method_name|
          skip_hash = send(method_name, formula_or_cask, livecheckable, full_name: full_name, verbose: verbose)
          return skip_hash if skip_hash.present?
        end

        {}
      end

      # Skip conditions for formulae/casks referenced in a `livecheck` block
      # are treated differently than normal. We only respect certain skip
      # conditions (returning the related hash) and others are treated as
      # errors.
      sig {
        params(
          livecheck_formula_or_cask:     T.any(Formula, Cask::Cask),
          original_formula_or_cask_name: String,
          full_name:                     T::Boolean,
          verbose:                       T::Boolean,
        ).returns(T.nilable(Hash))
      }
      def referenced_skip_information(
        livecheck_formula_or_cask,
        original_formula_or_cask_name,
        full_name: false,
        verbose: false
      )
        skip_info = SkipConditions.skip_information(
          livecheck_formula_or_cask,
          full_name: full_name,
          verbose:   verbose,
        )
        return if skip_info.blank?

        referenced_name = Livecheck.formula_or_cask_name(livecheck_formula_or_cask, full_name: full_name)
        referenced_type = case livecheck_formula_or_cask
        when Formula
          :formula
        when Cask::Cask
          :cask
        end

        if skip_info[:status] != "error" &&
           !(skip_info[:status] == "skipped" && livecheck_formula_or_cask.livecheck.skip?)
          error_msg_end = if skip_info[:status] == "skipped"
            "automatically skipped"
          else
            "skipped as #{skip_info[:status]}"
          end

          raise "Referenced #{referenced_type} (#{referenced_name}) is #{error_msg_end}"
        end

        skip_info[referenced_type] = original_formula_or_cask_name
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
        end
        return unless name

        if skip_hash[:messages].is_a?(Array) && skip_hash[:messages].count.positive?
          # TODO: Handle multiple messages, only if needed in the future
          if skip_hash[:status] == "skipped"
            puts "#{Tty.red}#{name}#{Tty.reset} : skipped - #{skip_hash[:messages][0]}"
          else
            puts "#{Tty.red}#{name}#{Tty.reset} : #{skip_hash[:messages][0]}"
          end
        elsif skip_hash[:status].present?
          puts "#{Tty.red}#{name}#{Tty.reset} : #{skip_hash[:status]}"
        end
      end
    end
  end
end
