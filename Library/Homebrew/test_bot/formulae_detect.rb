# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module TestBot
    class FormulaeDetect < Test
      attr_reader :testing_formulae, :added_formulae, :deleted_formulae

      def initialize(argument, tap:, git:, dry_run:, fail_fast:, verbose:)
        super(tap:, git:, dry_run:, fail_fast:, verbose:)

        @argument = argument
        @added_formulae = []
        @deleted_formulae = []
        @formulae_to_fetch = []
      end

      def run!(args:)
        detect_formulae!(args:)

        return unless GitHub::Actions.env_set?

        File.open(ENV.fetch("GITHUB_OUTPUT"), "a") do |f|
          f.puts "testing_formulae=#{@testing_formulae.join(",")}"
          f.puts "added_formulae=#{@added_formulae.join(",")}"
          f.puts "deleted_formulae=#{@deleted_formulae.join(",")}"
          f.puts "formulae_to_fetch=#{@formulae_to_fetch.join(",")}"
        end
      end

      private

      def detect_formulae!(args:)
        test_header(:FormulaeDetect, method: :detect_formulae!)

        url = nil
        origin_ref = "origin/main"

        github_repository = ENV.fetch("GITHUB_REPOSITORY", nil)
        github_ref = ENV.fetch("GITHUB_REF", nil)

        if @argument == "HEAD"
          @testing_formulae = []
          # Use GitHub Actions variables for pull request jobs.
          if github_ref.present? && github_repository.present? &&
             %r{refs/pull/(\d+)/merge} =~ github_ref
            url = "https://github.com/#{github_repository}/pull/#{Regexp.last_match(1)}/checks"
          end
        elsif (canonical_formula_name = safe_formula_canonical_name(@argument, args:))
          unless canonical_formula_name.include?("/")
            ENV["HOMEBREW_NO_INSTALL_FROM_API"] = "1"
            CoreTap.instance.ensure_installed!
          end

          @testing_formulae = [canonical_formula_name]
        else
          raise UsageError,
                "#{@argument} is not detected from GitHub Actions or a formula name!"
        end

        github_sha = ENV.fetch("GITHUB_SHA", nil)
        if github_repository.blank? || github_sha.blank? || github_ref.blank?
          if GitHub::Actions.env_set?
            odie <<~EOS
              We cannot find the needed GitHub Actions environment variables! Check you have e.g. exported them to a Docker container.
            EOS
          elsif ENV["CI"]
            onoe <<~EOS
              No known CI provider detected! If you are using GitHub Actions then we cannot find the expected environment variables! Check you have e.g. exported them to a Docker container.
            EOS
          end
        elsif tap.present? && tap.full_name.casecmp(github_repository).zero?
          # Use GitHub Actions variables for pull request jobs.
          if (base_ref = ENV.fetch("GITHUB_BASE_REF", nil)).present?
            unless tap.official?
              test git, "-C", repository, "fetch",
                   "origin", "+refs/heads/#{base_ref}"
            end
            origin_ref = "origin/#{base_ref}"
            diff_start_sha1 = rev_parse(origin_ref)
            diff_end_sha1 = github_sha
          # Use GitHub Actions variables for merge group jobs.
          elsif ENV.fetch("GITHUB_EVENT_NAME", nil) == "merge_group"
            diff_start_sha1 = rev_parse(origin_ref)
            origin_ref = "origin/#{github_ref.gsub(%r{^refs/heads/}, "")}"
            diff_end_sha1 = github_sha
          # Use GitHub Actions variables for branch jobs.
          else
            test git, "-C", repository, "fetch", "origin", "+#{github_ref}" unless tap.official?
            origin_ref = "origin/#{github_ref.gsub(%r{^refs/heads/}, "")}"
            diff_end_sha1 = diff_start_sha1 = github_sha
          end
        end

        if diff_start_sha1.present? && diff_end_sha1.present?
          merge_base_sha1 =
            Utils.safe_popen_read(git, "-C", repository, "merge-base",
                                  diff_start_sha1, diff_end_sha1).strip
          diff_start_sha1 = merge_base_sha1 if merge_base_sha1.present?
        end

        diff_start_sha1 = current_sha1 if diff_start_sha1.blank?
        diff_end_sha1 = current_sha1 if diff_end_sha1.blank?

        diff_start_sha1 = diff_end_sha1 if @testing_formulae.present?

        if tap
          tap_origin_ref_revision_args =
            [git, "-C", tap.path.to_s, "log", "-1", "--format=%h (%s)", origin_ref]
          tap_origin_ref_revision = if args.dry_run?
            # May fail on dry run as we've not fetched.
            Utils.popen_read(*tap_origin_ref_revision_args).strip
          else
            Utils.safe_popen_read(*tap_origin_ref_revision_args)
          end.strip
          tap_revision = Utils.safe_popen_read(
            git, "-C", tap.path.to_s,
            "log", "-1", "--format=%h (%s)"
          ).strip
        end

        puts <<-EOS
    url               #{url.presence                     || "(blank)"}
    tap #{origin_ref} #{tap_origin_ref_revision.presence || "(blank)"}
    HEAD              #{tap_revision.presence            || "(blank)"}
    diff_start_sha1   #{diff_start_sha1.presence         || "(blank)"}
    diff_end_sha1     #{diff_end_sha1.presence           || "(blank)"}
        EOS

        modified_formulae = []

        if tap && diff_start_sha1 != diff_end_sha1
          formula_path = tap.formula_dir.to_s
          @added_formulae +=
            diff_formulae(diff_start_sha1, diff_end_sha1, formula_path, "A")
          modified_formulae +=
            diff_formulae(diff_start_sha1, diff_end_sha1, formula_path, "M")
          @deleted_formulae +=
            diff_formulae(diff_start_sha1, diff_end_sha1, formula_path, "D")
        end

        # If a formula is both added and deleted: it's actually modified.
        added_and_deleted_formulae = @added_formulae & @deleted_formulae
        @added_formulae -= added_and_deleted_formulae
        @deleted_formulae -= added_and_deleted_formulae
        modified_formulae += added_and_deleted_formulae

        if args.test_default_formula?
          # Build the default test formulae.
          modified_formulae << "libfaketime" << "xz"
        elsif @added_formulae.present? &&
              @added_formulae.all? { |formula| formula.start_with?("portable-") }
          @added_formulae = ["portable-ruby"]
        elsif modified_formulae.present? &&
              modified_formulae.all? { |formula| formula.start_with?("portable-") }
          modified_formulae = ["portable-ruby"]
        elsif modified_formulae.any? { |formula| formula.start_with?("portable-") }
          odie "Portable Ruby (and related formulae) cannot be tested in the same job as other formulae!"
        end

        @testing_formulae += @added_formulae + modified_formulae

        # TODO: Remove `GITHUB_EVENT_NAME` check when formulae detection
        #       is fixed for branch jobs.
        if @testing_formulae.blank? &&
           @deleted_formulae.blank? &&
           diff_start_sha1 == diff_end_sha1 &&
           (ENV["GITHUB_EVENT_NAME"] != "push")
          raise UsageError, "Did not find any formulae or commits to test!"
        end

        # Remove all duplicates.
        @testing_formulae.uniq!
        @added_formulae.uniq!
        modified_formulae.uniq!
        @deleted_formulae.uniq!

        # We only need to do a fetch test on formulae that have had a change in the pkg version or bottle block.
        # These fetch tests only happen in merge queues.
        @formulae_to_fetch = if diff_start_sha1 == diff_end_sha1 || ENV["GITHUB_EVENT_NAME"] != "merge_group"
          []
        else
          require "formula_versions"

          @testing_formulae.reject do |formula_name|
            latest_formula = Formula[formula_name]

            # nil = formula not found, false = bottles changed, true = bottles not changed
            equal_bottles = FormulaVersions.new(latest_formula).formula_at_revision(diff_start_sha1) do |old_formula|
              old_formula.pkg_version == latest_formula.pkg_version &&
                old_formula.bottle_specification == latest_formula.bottle_specification
            end

            equal_bottles # only exclude the true case (bottles not changed)
          end
        end

        puts <<-EOS

    testing_formulae  #{@testing_formulae.join(" ").presence  || "(none)"}
    added_formulae    #{@added_formulae.join(" ").presence    || "(none)"}
    modified_formulae #{modified_formulae.join(" ").presence  || "(none)"}
    deleted_formulae  #{@deleted_formulae.join(" ").presence  || "(none)"}
    formulae_to_fetch #{@formulae_to_fetch.join(" ").presence || "(none)"}
        EOS
      end

      def safe_formula_canonical_name(formula_name, args:)
        Homebrew.with_no_api_env do
          Formulary.factory(formula_name).full_name
        end
      rescue TapFormulaUnavailableError => e
        raise if e.tap.installed?

        test "brew", "tap", e.tap.name
        retry unless steps.last.failed?
        onoe e
        puts e.backtrace if args.debug?
      rescue FormulaUnavailableError, TapFormulaAmbiguityError => e
        onoe e
        puts e.backtrace if args.debug?
      end

      def rev_parse(ref)
        Utils.popen_read(git, "-C", repository, "rev-parse", "--verify", ref).strip
      end

      def current_sha1
        rev_parse("HEAD")
      end

      def diff_formulae(start_revision, end_revision, path, filter)
        return unless tap

        Utils.safe_popen_read(
          git, "-C", repository,
          "diff-tree", "-r", "--name-only", "--diff-filter=#{filter}",
          start_revision, end_revision, "--", path
        ).lines(chomp: true).filter_map do |file|
          next unless tap.formula_file?(file)

          file = Pathname.new(file)
          tap.formula_file_to_name(file)
        end
      end
    end
  end
end
