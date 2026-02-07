# typed: strict
# frozen_string_literal: true

require "os"
require "tap"

module Homebrew
  module TestBot
    class TestCleanup < Test
      protected

      ALLOWED_TAPS = T.let([
        CoreTap.instance.name,
        CoreCaskTap.instance.name,
      ].freeze, T::Array[String])

      sig { params(repository: String).void }
      def reset_if_needed(repository)
        default_ref = default_origin_ref(repository)

        return if system(git.to_s, "-C", repository, "diff", "--quiet", default_ref)

        test git.to_s, "-C", repository, "reset", "--hard", default_ref
      end

      # Moving files is faster than removing them,
      # so move them if the current runner is ephemeral.
      sig { params(paths: T::Array[Pathname], sudo: T::Boolean).void }
      def delete_or_move(paths, sudo: false)
        return if paths.blank?

        symlinks, paths = paths.partition(&:symlink?)

        FileUtils.rm_f symlinks
        return if ENV["HOMEBREW_GITHUB_ACTIONS"].blank?

        paths.select!(&:exist?)
        return if paths.blank?

        if ENV["GITHUB_ACTIONS_HOMEBREW_SELF_HOSTED"].present?
          if sudo
            test "sudo", "rm", "-rf", *paths.map(&:to_s)
          else
            FileUtils.rm_rf paths
          end
        else
          paths.each do |path|
            if sudo
              test "sudo", "mv", path.to_s, Dir.mktmpdir
            else
              FileUtils.mv path, Dir.mktmpdir, force: true
            end
          end
        end
      end

      sig { void }
      def cleanup_shared
        FileUtils.chmod_R("u+X", HOMEBREW_CELLAR, force: true)

        if repository.exist?
          repo = repository.to_s
          cleanup_git_meta(repo)
          clean_if_needed(repo)
          prune_if_needed(repo)
        end

        if HOMEBREW_REPOSITORY != HOMEBREW_PREFIX
          paths_to_delete = []

          info_header "Determining #{HOMEBREW_PREFIX} files to purge..."
          Keg.must_be_writable_directories.each(&:mkpath)
          Pathname.glob("#{HOMEBREW_PREFIX}/**/*", File::FNM_DOTMATCH).each do |path|
            next if Keg.must_be_writable_directories.include?(path)
            next if path == HOMEBREW_PREFIX/"bin/brew"
            next if path == HOMEBREW_PREFIX/"var"
            next if path == HOMEBREW_PREFIX/"var/homebrew"

            basename = path.basename.to_s
            next if basename == "."
            next if basename == ".keepme"

            path_string = path.to_s
            next if path_string.start_with?(HOMEBREW_REPOSITORY.to_s)
            next if path_string.start_with?(Dir.pwd.to_s)

            # allow deleting non-existent osxfuse symlinks.
            if (!path.symlink? || path.resolved_path_exists?) &&
               # don't try to delete other osxfuse files
               path_string.match?("(include|lib)/(lib|osxfuse/|pkgconfig/)?(osx|mac)?fuse(.*.(dylib|h|la|pc))?$")
              next
            end

            FileUtils.chmod("u+rw", path) if path.owned? && (!path.readable? || !path.writable?)
            paths_to_delete << path
          end

          # Do this in a second pass so that all children have their permissions fixed before we delete the parent.
          info_header "Purging..."
          delete_or_move paths_to_delete
        end

        if tap
          checkout_branch_if_needed(HOMEBREW_REPOSITORY.to_s)
          reset_if_needed(HOMEBREW_REPOSITORY.to_s)
          clean_if_needed(HOMEBREW_REPOSITORY.to_s)
        end

        # Keep all "brew" invocations after HOMEBREW_REPOSITORY operations
        # (which cleans up Homebrew/brew)
        taps_to_remove = Tap.map do |t|
          next if t.name == tap&.name
          next if ALLOWED_TAPS.include?(t.name)

          t.path
        end.uniq.compact
        delete_or_move taps_to_remove

        Pathname.glob("#{HOMEBREW_LIBRARY}/Taps/*/*").each do |git_repo|
          git_repo_str = git_repo.to_s
          cleanup_git_meta(git_repo_str)
          next if repository == git_repo

          checkout_branch_if_needed(git_repo_str)
          reset_if_needed(git_repo_str)
          clean_if_needed(git_repo_str)
          prune_if_needed(git_repo_str)
        end

        # don't need to do `brew cleanup` unless we're self-hosted.
        return if ENV["HOMEBREW_GITHUB_ACTIONS"] && !ENV["GITHUB_ACTIONS_HOMEBREW_SELF_HOSTED"]

        test "brew", "cleanup", "--prune=3"
      end

      private

      sig { params(repository: String).returns(String) }
      def default_origin_ref(repository)
        default_branch = Utils.popen_read(
          git, "-C", repository, "symbolic-ref", "refs/remotes/origin/HEAD", "--short"
        ).strip.presence
        default_branch ||= "origin/main"
        default_branch
      end

      sig { params(repository: String).void }
      def checkout_branch_if_needed(repository)
        # We limit this to two parts, because branch names can have slashes in
        default_branch = default_origin_ref(repository).split("/", 2).last
        current_branch = Utils.safe_popen_read(
          git, "-C", repository, "symbolic-ref", "HEAD", "--short"
        ).strip
        return if default_branch == current_branch

        test git.to_s, "-C", repository, "checkout", "-f", default_branch.to_s
      end

      sig { params(repository: String).void }
      def cleanup_git_meta(repository)
        pr_locks = "#{repository}/.git/refs/remotes/*/pr/*/*.lock"
        Dir.glob(pr_locks) { |lock| FileUtils.rm_f lock }
        FileUtils.rm_f "#{repository}/.git/gc.log"
      end

      sig { params(repository: String).void }
      def clean_if_needed(repository)
        return if repository == HOMEBREW_PREFIX && HOMEBREW_PREFIX != HOMEBREW_REPOSITORY

        clean_args = [
          "-dx",
          "--exclude=/*.bottle*.*",
          "--exclude=/Library/Taps",
          "--exclude=/Library/Homebrew/vendor",
        ]
        return if Utils.safe_popen_read(
          git, "-C", repository, "clean", "--dry-run", *clean_args
        ).strip.empty?

        test git.to_s, "-C", repository, "clean", "-ff", *clean_args
      end

      sig { params(repository: String).void }
      def prune_if_needed(repository)
        return unless Utils.safe_popen_read(
          "#{git} -C '#{repository}' -c gc.autoDetach=false gc --auto 2>&1",
        ).include?("git prune")

        test git.to_s, "-C", repository, "prune"
      end
    end
  end
end
