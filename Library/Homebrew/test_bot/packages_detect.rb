# typed: strict
# frozen_string_literal: true

require "api/env"
require "test_bot/test"

module Homebrew
  module TestBot
    class PackagesDetect < Test
      # Formulae must have GitHub homepages and stable URLs, no dependencies,
      # one executable and one library between them.
      DEFAULT_TEST_FORMULAE = %w[termbox bats-core].freeze

      sig { returns(T::Array[String]) }
      attr_reader :testing_formulae, :added_formulae, :deleted_formulae, :testing_casks, :added_casks, :deleted_casks

      sig {
        params(
          argument:  String,
          tap:       T.nilable(Tap),
          git:       String,
          dry_run:   T::Boolean,
          fail_fast: T::Boolean,
          verbose:   T::Boolean,
        ).void
      }
      def initialize(argument, tap:, git:, dry_run:, fail_fast:, verbose:)
        super(tap:, git:, dry_run:, fail_fast:, verbose:)

        @testing_casks = T.let([], T::Array[String])
        @added_casks = T.let([], T::Array[String])
        @deleted_casks = T.let([], T::Array[String])
        @argument = argument
        @added_formulae = T.let([], T::Array[String])
        @deleted_formulae = T.let([], T::Array[String])
        @formulae_to_fetch = T.let([], T::Array[String])
        @testing_formulae = T.let([], T::Array[String])
      end

      sig { params(args: Homebrew::Cmd::TestBotCmd::Args).void }
      def run!(args:)
        name = @argument
        if name == "HEAD"
          raise UsageError, "Please specify a cask or a tap with --tap." if args.only_casks? && !tap

          detect_packages!(args:)
        elsif args.only_casks?
          name = "#{@tap.name}/#{name}" if @tap && name.exclude?("/")
          @testing_casks = [name]
        else
          only = :formula if args.only_formulae?
          package = CLI::NamedArgs.new(name, parent: args, without_api: true).to_formulae_and_casks(only:).fetch(0)
          case package
          when Formula
            if package.tap&.core_tap?
              ENV["HOMEBREW_NO_INSTALL_FROM_API"] = "1"
              CoreTap.instance.ensure_installed!
            end
            @testing_formulae = [package.full_name]
            @testing_formulae |= DEFAULT_TEST_FORMULAE if args.test_default_formula?
          when Cask::Cask
            @testing_casks = [package.full_name]
          end
        end

        return unless GitHub::Actions.env_set?

        File.open(ENV.fetch("GITHUB_OUTPUT"), "a") do |f|
          f.puts "testing_casks=#{@testing_casks.join(",")}"
          f.puts "added_casks=#{@added_casks.join(",")}"
          f.puts "deleted_casks=#{@deleted_casks.join(",")}"
          f.puts "testing_formulae=#{@testing_formulae.join(",")}"
          f.puts "added_formulae=#{@added_formulae.join(",")}"
          f.puts "deleted_formulae=#{@deleted_formulae.join(",")}"
          f.puts "formulae_to_fetch=#{@formulae_to_fetch.join(",")}"
        end
      end

      # Returns the added, modified and deleted package names in a Git revision range.
      sig {
        params(tap: Tap, revisions: String, check_cask_paths: T::Boolean)
          .returns(T::Hash[Symbol, [T::Array[String], T::Array[String], T::Array[String]]])
      }
      def self.changed_packages(tap, revisions, check_cask_paths: false)
        changes = Utils.safe_popen_read(
          Utils::Git.git, "-C", tap.path, "diff", "--no-renames", "--name-status", "-z", "--diff-filter=AMD",
          revisions, "--", "*.rb"
        )
        packages = T.let({ formula: {}, cask: {} }, T::Hash[Symbol, T::Hash[String, T::Array[String]]])
        misplaced = []
        changes.split("\0").each_slice(2) do |entry|
          status = entry.fetch(0)
          file = entry.fetch(1)

          if tap.cask_file?(file)
            by_status = packages.fetch(:cask)
          elsif check_cask_paths && status != "D" && !file.start_with?("cmd/", ".github/actions/")
            misplaced << file
            next
          elsif tap.formula_file?(file)
            by_status = packages.fetch(:formula)
          else
            next
          end
          (by_status[status] ||= []) << tap.formula_file_to_name(Pathname(file))
        end

        if misplaced.any?
          misplaced.each { |file| puts "::error file=#{file}::File is in wrong directory." }
          raise "Found Ruby files in wrong directory:\n#{misplaced.join("\n")}"
        end

        # Moving a package between subdirectories changes its path but keeps its name.
        packages.transform_values do |by_status|
          added = by_status.fetch("A", [])
          deleted = by_status.fetch("D", [])
          [added - deleted, by_status.fetch("M", []) | (added & deleted), deleted - added]
        end
      end

      private

      sig { params(args: Homebrew::Cmd::TestBotCmd::Args).void }
      def detect_packages!(args:)
        test_header(:PackagesDetect, method: :detect_packages!)

        url = nil
        origin_ref = "origin/HEAD"

        github_repository = ENV.fetch("GITHUB_REPOSITORY", nil)
        github_ref = ENV.fetch("GITHUB_REF", nil)

        if github_ref.present? && github_repository.present? && %r{refs/pull/(\d+)/merge} =~ github_ref
          url = "https://github.com/#{github_repository}/pull/#{Regexp.last_match(1)}/checks"
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
          elsif @tap
            if @tap.git_repository.origin_branch_name
              diff_start_sha1 = rev_parse(origin_ref)
            else
              origin_ref = "HEAD"
              diff_start_sha1 = rev_parse("HEAD^")
            end
            diff_end_sha1 = current_sha1
          end
        elsif (tap = self.tap.presence) && tap.full_name.casecmp(github_repository)&.zero?
          # Use GitHub Actions variables for pull request jobs.
          if (base_ref = ENV.fetch("GITHUB_BASE_REF", nil)).present?
            unless tap.official?
              test git.to_s, "-C", repository.to_s, "fetch",
                   "origin", "+refs/heads/#{base_ref}"
            end
            origin_ref = "origin/#{base_ref}"
            diff_start_sha1 = rev_parse(origin_ref)
            diff_end_sha1 = github_sha
          # Use GitHub Actions variables for merge group jobs.
          elsif ENV.fetch("GITHUB_EVENT_NAME", nil) == "merge_group"
            origin_ref = "origin/main" if rev_parse(origin_ref).blank?
            diff_start_sha1 = rev_parse(origin_ref)
            raise UsageError, "Cannot resolve merge group base #{origin_ref}." if diff_start_sha1.blank?

            diff_end_sha1 = github_sha
          # Use GitHub Actions variables for branch jobs.
          else
            test git.to_s, "-C", repository.to_s, "fetch", "origin", "+#{github_ref}" unless tap.official?
            origin_ref = "origin/#{github_ref.gsub(%r{^refs/heads/}, "")}"
            diff_end_sha1 = diff_start_sha1 = github_sha
          end
        end

        if diff_start_sha1.present? && diff_end_sha1.present?
          merge_base_sha1 =
            Utils.safe_popen_read(git, "-C", repository, "merge-base",
                                  diff_start_sha1, diff_end_sha1).strip
          diff_start_sha1 = merge_base_sha1 if merge_base_sha1.present?
        elsif origin_ref == "HEAD"
          # A newly created tap can have a single commit and no remote.
          diff_start_sha1 = Utils.safe_popen_read(git, "-C", repository, "hash-object", "-t", "tree", File::NULL).chomp
        end

        diff_start_sha1 = current_sha1 if diff_start_sha1.blank?
        diff_end_sha1 = current_sha1 if diff_end_sha1.blank?

        if (tap = self.tap.presence)
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

        display_url = url.presence || "(blank)"
        origin_revision = tap_origin_ref_revision.presence || "(blank)"
        display_revision = tap_revision.presence || "(blank)"
        start_revision = diff_start_sha1.presence || "(blank)"
        end_revision = diff_end_sha1.presence || "(blank)"
        puts <<-EOS
    url               #{display_url}
    tap #{origin_ref} #{origin_revision}
    HEAD              #{display_revision}
    diff_start_sha1   #{start_revision}
    diff_end_sha1     #{end_revision}
        EOS

        modified_formulae = []

        if diff_start_sha1 != diff_end_sha1 && (tap = self.tap.presence)
          packages = self.class.changed_packages(tap, "#{diff_start_sha1}..#{diff_end_sha1}",
                                                 check_cask_paths: tap.core_cask_tap?)
          @added_formulae, modified_formulae, @deleted_formulae = packages.fetch(:formula) unless args.only_casks?
          unless args.only_formulae?
            @added_casks, modified_casks, @deleted_casks = packages.fetch(:cask)
            @testing_casks = @added_casks | modified_casks
          end
        end

        if args.test_default_formula?
          @added_formulae.reject! { |formula| formula.start_with?("portable-") }
          modified_formulae.reject! { |formula| formula.start_with?("portable-") }
          # Build the default test formulae.
          modified_formulae += DEFAULT_TEST_FORMULAE
        elsif @added_formulae.present? &&
              @added_formulae.all? { |formula| formula.start_with?("portable-") }
          @added_formulae = ["portable-ruby"]
        elsif modified_formulae.present? &&
              modified_formulae.all? { |formula| formula.start_with?("portable-") }
          modified_formulae = ["portable-ruby"]
        elsif modified_formulae.any? { |formula| formula.start_with?("portable-") } &&
              !(ENV["GITHUB_EVENT_NAME"] == "merge_group" && args.only_packages_detect?)
          odie "Portable Ruby (and related formulae) cannot be tested in the same job as other formulae!"
        end

        @testing_formulae += @added_formulae + modified_formulae

        # TODO: Remove `GITHUB_EVENT_NAME` check when package detection
        #       is fixed for branch jobs.
        if @testing_formulae.blank? && @testing_casks.blank? && !args.only_casks? &&
           @deleted_formulae.blank? && !args.only_packages_detect? &&
           diff_start_sha1 == diff_end_sha1 &&
           (ENV["GITHUB_EVENT_NAME"] != "push")
          raise UsageError, "Did not find any formulae or commits to test!"
        end

        # Remove all duplicates.
        @testing_formulae.uniq!

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

        summary = {
          testing_formulae:  @testing_formulae,
          added_formulae:    @added_formulae,
          modified_formulae:,
          deleted_formulae:  @deleted_formulae,
          formulae_to_fetch: @formulae_to_fetch,
        }
        if args.only_packages_detect? || @testing_casks.present? || @deleted_casks.present?
          summary.merge!(testing_casks: @testing_casks, added_casks: @added_casks,
                         modified_casks: modified_casks.to_a, deleted_casks: @deleted_casks)
        end
        puts
        summary.each do |label, names|
          puts format("    %<label>-17s %<names>s", label:, names: names.join(" ").presence || "(none)")
        end
      end

      sig { params(ref: String).returns(String) }
      def rev_parse(ref)
        Utils.popen_read(git, "-C", repository, "rev-parse", "--verify", "--quiet", ref).strip
      end

      sig { returns(String) }
      def current_sha1
        rev_parse("HEAD")
      end
    end
  end
end
