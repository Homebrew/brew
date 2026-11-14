# typed: strict
# frozen_string_literal: true

module Homebrew
  module Livecheck
    # Release selection and version-update history for throttling.
    module Throttle
      extend T::Helpers

      requires_ancestor { T.class_of(Livecheck) }

      sig {
        params(formula_or_cask: T.any(Formula, Cask::Cask), match_version_map: T::Hash[String, Version],
               latest: Version, throttle_rate: T.nilable(Integer), throttle_days: T.nilable(Integer), debug: T::Boolean,
               verbose: T::Boolean).returns(T.nilable(Version))
      }
      def throttled_version(formula_or_cask, match_version_map, latest, throttle_rate: nil, throttle_days: nil,
                            debug: false, verbose: false)
        throttled_match_version_map = if throttle_rate
          match_version_map.select do |_match, version|
            throttle_allows_bump?(formula_or_cask, version, throttle_rate:)
          end
        else
          {}
        end

        latest_throttled = if throttle_days &&
                              throttle_allows_bump?(formula_or_cask, latest, throttle_days:)
          latest
        elsif (version = throttled_match_version_map.values.max_by do |v|
          LivecheckVersion.create(formula_or_cask, v)
        end)
          Version.new(version)
        end

        if debug
          print_matches(throttled_match_version_map, heading: "Matched Throttled Versions", verbose:)

          if latest_throttled == latest && throttled_match_version_map.blank?
            puts Tty.strip_ansi("#{latest_throttled} (throttle interval elapsed)")
          end
        end
        latest_throttled
      end

      sig {
        params(
          formula_or_cask: T.any(Formula, Cask::Cask),
          version:         T.any(String, Version),
          throttle_rate:   T.nilable(Integer),
          throttle_days:   T.nilable(Integer),
        ).returns(T::Boolean)
      }
      def throttle_allows_bump?(formula_or_cask, version, throttle_rate: nil, throttle_days: nil)
        return true if throttle_rate.nil? && throttle_days.nil?

        unless throttle_rate.nil?
          version = Version.new(version) unless version.is_a?(Version)
          return true if version.patch.to_i.modulo(throttle_rate).zero?
        end

        !throttle_days.nil? && throttle_interval_elapsed?(formula_or_cask, throttle_days)
      end

      sig { params(formula_or_cask: T.any(Formula, Cask::Cask)).returns(T.nilable(Integer)) }
      def formula_or_cask_last_updated_timestamp(formula_or_cask)
        tap = formula_or_cask.tap
        return if tap.nil?
        return unless tap.git?
        return unless Utils::Git.available?

        if formula_or_cask.is_a?(Formula)
          timestamp = formula_last_version_update_timestamp(formula_or_cask, tap:)
          return timestamp if timestamp.present?
        end

        formula_or_cask_last_commit_timestamp(formula_or_cask, tap)
      end

      sig { params(formula_or_cask: T.any(Formula, Cask::Cask), days: Integer).returns(T::Boolean) }
      def throttle_interval_elapsed?(formula_or_cask, days)
        return false if days <= 0

        last_updated_timestamp = formula_or_cask_last_updated_timestamp(formula_or_cask)
        return false if last_updated_timestamp.nil?

        elapsed_seconds = Time.now.to_i - last_updated_timestamp
        elapsed_seconds >= (days * 24 * 60 * 60)
      end

      private

      sig { params(formula: Formula, tap: Tap).returns(T.nilable(Integer)) }
      def formula_last_version_update_timestamp(formula, tap:)
        stable = formula.stable
        return if stable.blank?

        version_update_revision = find_version_update_revision(formula, stable.version)
        return if version_update_revision.nil?

        timestamp_for_revision(tap.path, version_update_revision)
      end

      sig { params(formula: Formula, current_version: Version).returns(T.nilable(String)) }
      def find_version_update_revision(formula, current_version)
        version_update_revision = T.let(nil, T.nilable(String))
        found_current_version = T.let(false, T::Boolean)

        formula_versions = FormulaVersions.new(formula)
        current_version = origin_stable_version(formula, formula_versions) || current_version

        formula_versions.rev_list("HEAD") do |revision, path|
          formula_versions.formula_at_revision(revision, path) do |historical_formula|
            historical_stable = historical_formula.stable
            next if historical_stable.blank?

            if historical_stable.version == current_version
              found_current_version = true
              version_update_revision = revision
            elsif found_current_version
              return version_update_revision
            end
          end
        rescue MacOSVersion::Error, LegacyDSLError
          break
        end

        version_update_revision
      end

      sig { params(formula: Formula, formula_versions: FormulaVersions).returns(T.nilable(Version)) }
      def origin_stable_version(formula, formula_versions)
        tap = formula.tap
        return if tap.nil?

        revision = Utils.popen_read(
          Utils::Git.git, "rev-parse", "origin/HEAD",
          chdir: tap.path
        ).chomp.presence
        return if revision.nil?

        relative_path = formula.path.relative_path_from(tap.path).to_s
        version = T.let(nil, T.nilable(Version))
        formula_versions.formula_at_revision(revision, relative_path) do |historical_formula|
          version = historical_formula.stable&.version
        end
        version
      rescue MacOSVersion::Error, LegacyDSLError
        nil
      end

      sig {
        params(formula_or_cask: T.any(Formula, Cask::Cask), tap: Tap).returns(T.nilable(Integer))
      }
      def formula_or_cask_last_commit_timestamp(formula_or_cask, tap)
        sourcefile = case formula_or_cask
        when Formula
          formula_or_cask.path
        when Cask::Cask
          formula_or_cask.sourcefile_path
        end
        return if sourcefile.nil?

        default_branch = Utils.popen_read(
          Utils::Git.git,
          "symbolic-ref",
          "refs/remotes/origin/HEAD",
          "--short",
          chdir: tap.path,
          err:   :close,
        ).chomp.presence

        # A detached checkout, as used for pull request CI, has no local branch,
        # so fall back to the remote-tracking ref and finally the current commit.
        refs = [
          default_branch,
          default_branch&.delete_prefix("origin/"),
          "origin/HEAD",
          "origin/main",
          "main",
          "HEAD",
        ].compact.uniq

        relative_sourcefile = sourcefile.relative_path_from(tap.path).to_s
        timestamp = refs.lazy.filter_map do |ref|
          Utils.popen_read(
            Utils::Git.git,
            "log",
            ref,
            "-1",
            "--format=%ct",
            "--",
            relative_sourcefile,
            chdir: tap.path,
            err:   :close,
          ).chomp.presence
        end.first
        return if timestamp.nil?

        Integer(timestamp, exception: false)
      rescue ArgumentError
        nil
      end

      sig { params(repository_path: Pathname, revision: String).returns(T.nilable(Integer)) }
      def timestamp_for_revision(repository_path, revision)
        timestamp = Utils.popen_read(
          Utils::Git.git,
          "show",
          "-s",
          "--format=%ct",
          revision,
          chdir: repository_path,
        ).chomp.presence
        return if timestamp.nil?

        Integer(timestamp, exception: false)
      rescue ArgumentError
        nil
      end
    end
  end
end
