# frozen_string_literal: true

module Bundler
  class Source
    class Git
      class GitNotInstalledError < GitError
        def initialize
          msg = String.new
          msg << "You need to install git to be able to use gems from git repositories. "
          msg << "For help installing git, please refer to GitHub's tutorial at https://help.github.com/articles/set-up-git"
          super msg
        end
      end

      class GitNotAllowedError < GitError
        def initialize(command)
          msg = String.new
          msg << "Bundler is trying to run `#{command}` at runtime. You probably need to run `bundle install`. However, "
          msg << "this error message could probably be more useful. Please submit a ticket at https://github.com/rubygems/rubygems/issues/new?labels=Bundler&template=bundler-related-issue.md "
          msg << "with steps to reproduce as well as the following\n\nCALLER: #{caller.join("\n")}"
          super msg
        end
      end

      class GitCommandError < GitError
        attr_reader :command

        def initialize(command, path, extra_info = nil)
          @command = command

          msg = String.new("Git error: command `#{command}`")
          msg << " in directory #{path}" if path
          msg << " has failed."
          msg << "\n#{extra_info}" if extra_info
          super msg
        end
      end

      class MissingGitRevisionError < GitCommandError
        def initialize(command, destination_path, ref, repo)
          msg = "Revision #{ref} does not exist in the repository #{repo}. Maybe you misspelled it?"
          super command, destination_path, msg
        end
      end

      class AmbiguousGitReference < GitError
        def initialize(options)
          msg = "Specification of branch or ref with tag is ambiguous. You specified #{options.inspect}"
          super msg
        end
      end

      # The GitProxy is responsible to interact with git repositories.
      # All actions required by the Git source is encapsulated in this
      # object.
      class GitProxy
        attr_accessor :path, :uri, :branch, :tag, :ref, :explicit_ref
        attr_writer :revision

        def initialize(path, uri, options = {}, revision = nil, git = nil)
          @path     = path
          @uri      = uri
          @tag      = options["tag"]
          @branch   = options["branch"]
          @ref      = options["ref"]
          if @tag
            raise AmbiguousGitReference.new(options) if @branch || @ref
            @explicit_ref = @tag
          else
            @explicit_ref = @ref || @branch
          end
          @revision = revision
          @git      = git
          @commit_ref = nil
        end

        def revision
          @revision ||= allowed_with_path { find_local_revision }
        end

        def current_branch
          @current_branch ||= with_path do
            git_local("rev-parse", "--abbrev-ref", "HEAD", dir: path).strip
          end
        end

        def not_a_repository?
          _, status = git_null("rev-parse", "--resolve-git-dir", path.to_s, dir: path)

          !status.success?
        end

        def contains?(commit)
          allowed_with_path do
            result, status = git_null("branch", "--contains", commit, dir: path)
            status.success? && result.match?(/^\* (.*)$/)
          end
        end

        def version
          @version ||= full_version.match(/((\.?\d+)+).*/)[1]
        end

        def full_version
          @full_version ||= git_local("--version").sub(/git version\s*/, "").strip
        end

        def checkout
          return if has_revision_cached?

          Bundler.ui.info "Fetching #{credential_filtered_uri}"

          extra_fetch_needed = clone_needs_extra_fetch?
          unshallow_needed = clone_needs_unshallow?
          return unless extra_fetch_needed || unshallow_needed

          git_remote_fetch(unshallow_needed ? ["--unshallow"] : depth_args)
        end

        def copy_to(destination, submodules = false)
          unless File.exist?(destination.join(".git"))
            begin
              SharedHelpers.filesystem_access(destination.dirname) do |p|
                FileUtils.mkdir_p(p)
              end
              SharedHelpers.filesystem_access(destination) do |p|
                FileUtils.rm_rf(p)
              end
              git "clone", "--no-checkout", "--quiet", path.to_s, destination.to_s
              File.chmod(((File.stat(destination).mode | 0o777) & ~File.umask), destination)
            rescue Errno::EEXIST => e
              file_path = e.message[%r{.*?((?:[a-zA-Z]:)?/.*)}, 1]
              raise GitError, "Bundler could not install a gem because it needs to " \
                "create a directory, but a file exists - #{file_path}. Please delete " \
                "this file and try again."
            end
          end

          ref = @commit_ref || (locked_to_full_sha? && @revision)
          if ref
            git "config", "uploadpack.allowAnySHA1InWant", "true", dir: path.to_s if @commit_ref.nil? && needs_allow_any_sha1_in_want?

            git "fetch", "--force", "--quiet", *extra_fetch_args(ref), dir: destination
          end

          git "reset", "--hard", @revision, dir: destination

          if submodules
            git_retry "submodule", "update", "--init", "--recursive", dir: destination
          elsif Gem::Version.create(version) >= Gem::Version.create("2.9.0")
            inner_command = "git -C $toplevel submodule deinit --force $sm_path"
            git_retry "submodule", "foreach", "--quiet", inner_command, dir: destination
          end
        end

        private

        def git_remote_fetch(args)
          command = ["fetch", "--force", "--quiet", "--no-tags", *args, "--", configured_uri, refspec].compact
          command_with_no_credentials = check_allowed(command)

          Bundler::Retry.new("`#{command_with_no_credentials}` at #{path}", [MissingGitRevisionError]).attempts do
            out, err, status = capture(command, path)
            return out if status.success?

            if err.include?("couldn't find remote ref") || err.include?("not our ref")
              raise MissingGitRevisionError.new(command_with_no_credentials, path, commit || explicit_ref, credential_filtered_uri)
            else
              raise GitCommandError.new(command_with_no_credentials, path, err)
            end
          end
        end

        def clone_needs_extra_fetch?
          return true if path.exist?

          SharedHelpers.filesystem_access(path.dirname) do |p|
            FileUtils.mkdir_p(p)
          end

          command = ["clone", "--bare", "--no-hardlinks", "--quiet", *extra_clone_args, "--", configured_uri, path.to_s]
          command_with_no_credentials = check_allowed(command)

          Bundler::Retry.new("`#{command_with_no_credentials}`", [MissingGitRevisionError]).attempts do
            _, err, status = capture(command, nil)
            return extra_ref if status.success?

            if err.include?("Could not find remote branch")
              raise MissingGitRevisionError.new(command_with_no_credentials, nil, explicit_ref, credential_filtered_uri)
            else
              idx = command.index("--depth")
              if idx
                command.delete_at(idx)
                command.delete_at(idx)
                command_with_no_credentials = check_allowed(command)

                err += "Retrying without --depth argument."
              end
              raise GitCommandError.new(command_with_no_credentials, path, err)
            end
          end
        end

        def clone_needs_unshallow?
          return false unless path.join("shallow").exist?
          return true if full_clone?

          @revision && @revision != head_revision
        end

        def extra_ref
          return false if not_pinned?
          return true unless full_clone?

          ref.start_with?("refs/")
        end

        def depth
          return @depth if defined?(@depth)

          @depth = if !supports_fetching_unreachable_refs?
            nil
          elsif not_pinned? || pinned_to_full_sha?
            1
          elsif ref.include?("~")
            parsed_depth = ref.split("~").last
            parsed_depth.to_i + 1
          end
        end

        def refspec
          if commit
            @commit_ref = "refs/#{commit}-sha"
            return "#{commit}:#{@commit_ref}"
          end

          reference = fully_qualified_ref

          reference ||= if ref.include?("~")
            ref.split("~").first
          elsif ref.start_with?("refs/")
            ref
          else
            "refs/*"
          end

          "#{reference}:#{reference}"
        end

        def commit
          @commit ||= pinned_to_full_sha? ? ref : @revision
        end

        def fully_qualified_ref
          if branch
            "refs/heads/#{branch}"
          elsif tag
            "refs/tags/#{tag}"
          elsif ref.nil?
            "refs/heads/#{current_branch}"
          end
        end

        def not_pinned?
          branch || tag || ref.nil?
        end

        def pinned_to_full_sha?
          full_sha_revision?(ref)
        end

        def locked_to_full_sha?
          full_sha_revision?(@revision)
        end

        def full_sha_revision?(ref)
          ref&.match?(/\A\h{40}\z/)
        end

        def git_null(*command, dir: nil)
          check_allowed(command)

          capture(command, dir, ignore_err: true)
        end

        def git_retry(*command, dir: nil)
          command_with_no_credentials = check_allowed(command)

          Bundler::Retry.new("`#{command_with_no_credentials}` at #{dir || SharedHelpers.pwd}").attempts do
            git(*command, dir: dir)
          end
        end

        def git(*command, dir: nil)
          run_command(*command, dir: dir) do |unredacted_command|
            check_allowed(unredacted_command)
          end
        end

        def git_local(*command, dir: nil)
          run_command(*command, dir: dir) do |unredacted_command|
            redact_and_check_presence(unredacted_command)
          end
        end

        def has_revision_cached?
          return unless @revision && path.exist?
          git("cat-file", "-e", @revision, dir: path)
          true
        rescue GitError
          false
        end

        def find_local_revision
          return head_revision if explicit_ref.nil?

          find_revision_for(explicit_ref)
        end

        def head_revision
          verify("HEAD")
        end

        def find_revision_for(reference)
          verify(reference)
        rescue GitCommandError => e
          raise MissingGitRevisionError.new(e.command, path, reference, credential_filtered_uri)
        end

        def verify(reference)
          git("rev-parse", "--verify", reference, dir: path).strip
        end

        # Adds credentials to the URI
        def configured_uri
          if /https?:/.match?(uri)
            remote = Gem::URI(uri)
            config_auth = Bundler.settings[remote.to_s] || Bundler.settings[remote.host]
            remote.userinfo ||= config_auth
            remote.to_s
          else
            uri.to_s
          end
        end

        # Removes credentials from the URI
        def credential_filtered_uri
          URICredentialsFilter.credential_filtered_uri(uri)
        end

        def allow?
          allowed = @git ? @git.allow_git_ops? : true

          raise GitNotInstalledError.new if allowed && !Bundler.git_present?

          allowed
        end

        def with_path(&blk)
          checkout unless path.exist?
          blk.call
        end

        def allowed_with_path
          return with_path { yield } if allow?
          raise GitError, "The git source #{uri} is not yet checked out. Please run `bundle install` before trying to start your application"
        end

        def check_allowed(command)
          command_with_no_credentials = redact_and_check_presence(command)
          raise GitNotAllowedError.new(command_with_no_credentials) unless allow?
          command_with_no_credentials
        end

        def redact_and_check_presence(command)
          raise GitNotInstalledError.new unless Bundler.git_present?

          require "shellwords"
          URICredentialsFilter.credential_filtered_string("git #{command.shelljoin}", uri)
        end

        def run_command(*command, dir: nil)
          command_with_no_credentials = yield(command)

          out, err, status = capture(command, dir)

          raise GitCommandError.new(command_with_no_credentials, dir || SharedHelpers.pwd, err) unless status.success?

          Bundler.ui.warn err unless err.empty?

          out
        end

        def capture(cmd, dir, ignore_err: false)
          SharedHelpers.with_clean_git_env do
            require "open3"
            out, err, status = Open3.capture3(*capture3_args_for(cmd, dir))

            filtered_out = URICredentialsFilter.credential_filtered_string(out, uri)
            return [filtered_out, status] if ignore_err

            filtered_err = URICredentialsFilter.credential_filtered_string(err, uri)
            [filtered_out, filtered_err, status]
          end
        end

        def capture3_args_for(cmd, dir)
          return ["git", *cmd] unless dir

          if Bundler.feature_flag.bundler_3_mode? || supports_minus_c?
            ["git", "-C", dir.to_s, *cmd]
          else
            ["git", *cmd, { chdir: dir.to_s }]
          end
        end

        def extra_clone_args
          args = depth_args
          return [] if args.empty?

          args += ["--single-branch"]
          args.unshift("--no-tags") if supports_cloning_with_no_tags?

          # If there's a locked revision, no need to clone any specific branch
          # or tag, since we will end up checking out that locked revision
          # anyways.
          return args if @revision

          args += ["--branch", branch || tag] if branch || tag
          args
        end

        def depth_args
          return [] if full_clone?

          ["--depth", depth.to_s]
        end

        def extra_fetch_args(ref)
          extra_args = [path.to_s, *depth_args]
          extra_args.push(ref)
          extra_args
        end

        def full_clone?
          depth.nil?
        end

        def supports_minus_c?
          @supports_minus_c ||= Gem::Version.new(version) >= Gem::Version.new("1.8.5")
        end

        def needs_allow_any_sha1_in_want?
          @needs_allow_any_sha1_in_want ||= Gem::Version.new(version) <= Gem::Version.new("2.13.7")
        end

        def supports_fetching_unreachable_refs?
          @supports_fetching_unreachable_refs ||= Gem::Version.new(version) >= Gem::Version.new("2.5.0")
        end

        def supports_cloning_with_no_tags?
          @supports_cloning_with_no_tags ||= Gem::Version.new(version) >= Gem::Version.new("2.14.0-rc0")
        end
      end
    end
  end
end
