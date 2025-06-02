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

          msg = String.new
          msg << "Git error: command `#{command}` in directory #{path} has failed."
          msg << "\n#{extra_info}" if extra_info
          msg << "\nIf this error persists you could try removing the cache directory '#{path}'" if path.exist?
          super msg
        end
      end

      class MissingGitRevisionError < GitCommandError
        def initialize(command, destination_path, ref, repo)
          msg = "Revision #{ref} does not exist in the repository #{repo}. Maybe you misspelled it?"
          super command, destination_path, msg
        end
      end

      # The GitProxy is responsible to interact with git repositories.
      # All actions required by the Git source is encapsulated in this
      # object.
      class GitProxy
        attr_accessor :path, :uri, :ref
        attr_writer :revision

        def initialize(path, uri, ref, revision = nil, git = nil)
          @path     = path
          @uri      = uri
          @ref      = ref
          @revision = revision
          @git      = git
        end

        def revision
          @revision ||= find_local_revision
        end

        def branch
          @branch ||= allowed_with_path do
            git("rev-parse", "--abbrev-ref", "HEAD", :dir => path).strip
          end
        end

        def contains?(commit)
          allowed_with_path do
            result, status = git_null("branch", "--contains", commit, :dir => path)
            status.success? && result =~ /^\* (.*)$/
          end
        end

        def version
          git("--version").match(/(git version\s*)?((\.?\d+)+).*/)[2]
        end

        def full_version
          git("--version").sub("git version", "").strip
        end

        def checkout
          return if path.exist? && has_revision_cached?
          extra_ref = "#{ref}:#{ref}" if ref && ref.start_with?("refs/")

          Bundler.ui.info "Fetching #{URICredentialsFilter.credential_filtered_uri(uri)}"

          configured_uri = configured_uri_for(uri).to_s

          unless path.exist?
            SharedHelpers.filesystem_access(path.dirname) do |p|
              FileUtils.mkdir_p(p)
            end
            git_retry "clone", "--bare", "--no-hardlinks", "--quiet", "--", configured_uri, path.to_s
            return unless extra_ref
          end

          with_path do
            git_retry(*["fetch", "--force", "--quiet", "--tags", "--", configured_uri, "refs/heads/*:refs/heads/*", extra_ref].compact, :dir => path)
          end
        end

        def copy_to(destination, submodules = false)
          # method 1
          unless File.exist?(destination.join(".git"))
            begin
              SharedHelpers.filesystem_access(destination.dirname) do |p|
                FileUtils.mkdir_p(p)
              end
              SharedHelpers.filesystem_access(destination) do |p|
                FileUtils.rm_rf(p)
              end
              git_retry "clone", "--no-checkout", "--quiet", path.to_s, destination.to_s
              File.chmod(((File.stat(destination).mode | 0o777) & ~File.umask), destination)
            rescue Errno::EEXIST => e
              file_path = e.message[%r{.*?((?:[a-zA-Z]:)?/.*)}, 1]
              raise GitError, "Bundler could not install a gem because it needs to " \
                "create a directory, but a file exists - #{file_path}. Please delete " \
                "this file and try again."
            end
          end
          # method 2
          git_retry "fetch", "--force", "--quiet", "--tags", path.to_s, :dir => destination

          begin
            git "reset", "--hard", @revision, :dir => destination
          rescue GitCommandError => e
            raise MissingGitRevisionError.new(e.command, destination, @revision, URICredentialsFilter.credential_filtered_uri(uri))
          end

          if submodules
            git_retry "submodule", "update", "--init", "--recursive", :dir => destination
          elsif Gem::Version.create(version) >= Gem::Version.create("2.9.0")
            inner_command = "git -C $toplevel submodule deinit --force $sm_path"
            git_retry "submodule", "foreach", "--quiet", inner_command, :dir => destination
          end
        end

        private

        def git_null(*command, dir: nil)
          check_allowed(command)

          out, status = SharedHelpers.with_clean_git_env do
            capture_and_ignore_stderr(*capture3_args_for(command, dir))
          end

          [URICredentialsFilter.credential_filtered_string(out, uri), status]
        end

        def git_retry(*command, dir: nil)
          command_with_no_credentials = check_allowed(command)

          Bundler::Retry.new("`#{command_with_no_credentials}` at #{dir || SharedHelpers.pwd}").attempts do
            git(*command, :dir => dir)
          end
        end

        def git(*command, dir: nil)
          command_with_no_credentials = check_allowed(command)

          out, status = SharedHelpers.with_clean_git_env do
            capture_and_filter_stderr(*capture3_args_for(command, dir))
          end

          filtered_out = URICredentialsFilter.credential_filtered_string(out, uri)

          raise GitCommandError.new(command_with_no_credentials, dir || SharedHelpers.pwd, filtered_out) unless status.success?

          filtered_out
        end

        def has_revision_cached?
          return unless @revision
          with_path { git("cat-file", "-e", @revision, :dir => path) }
          true
        rescue GitError
          false
        end

        def remove_cache
          FileUtils.rm_rf(path)
        end

        def find_local_revision
          allowed_with_path do
            git("rev-parse", "--verify", ref || "HEAD", :dir => path).strip
          end
        rescue GitCommandError => e
          raise MissingGitRevisionError.new(e.command, path, ref, URICredentialsFilter.credential_filtered_uri(uri))
        end

        # Adds credentials to the URI as Fetcher#configured_uri_for does
        def configured_uri_for(uri)
          if /https?:/ =~ uri
            remote = Bundler::URI(uri)
            config_auth = Bundler.settings[remote.to_s] || Bundler.settings[remote.host]
            remote.userinfo ||= config_auth
            remote.to_s
          else
            uri
          end
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
          require "shellwords"
          command_with_no_credentials = URICredentialsFilter.credential_filtered_string("git #{command.shelljoin}", uri)
          raise GitNotAllowedError.new(command_with_no_credentials) unless allow?
          command_with_no_credentials
        end

        def capture_and_filter_stderr(*cmd)
          require "open3"
          return_value, captured_err, status = Open3.capture3(*cmd)
          Bundler.ui.warn URICredentialsFilter.credential_filtered_string(captured_err, uri) unless captured_err.empty?
          [return_value, status]
        end

        def capture_and_ignore_stderr(*cmd)
          require "open3"
          return_value, _, status = Open3.capture3(*cmd)
          [return_value, status]
        end

        def capture3_args_for(cmd, dir)
          return ["git", *cmd] unless dir

          if Bundler.feature_flag.bundler_3_mode? || supports_minus_c?
            ["git", "-C", dir.to_s, *cmd]
          else
            ["git", *cmd, { :chdir => dir.to_s }]
          end
        end

        def supports_minus_c?
          @supports_minus_c ||= Gem::Version.new(version) >= Gem::Version.new("1.8.5")
        end
      end
    end
  end
end
