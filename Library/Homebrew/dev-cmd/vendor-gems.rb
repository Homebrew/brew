# typed: strict
# frozen_string_literal: true

require "system_command"

require "abstract_command"
require "utils/git"
require "fileutils"
require "utils/github"

module Homebrew
  module DevCmd
    class VendorGems < AbstractCommand
      cmd_args do
        description <<~EOS
          Install and commit Homebrew's vendored gems.
        EOS
        comma_array "--update",
                    description: "Update the specified list of vendored gems to the latest version."
        switch "--no-commit",
               description: "Do not generate a new commit upon completion."
        switch "--non-bundler-gems",
               description: "Update vendored gems that aren't using Bundler.",
               hidden:      true

        named_args :none
      end

      sig { override.void }
      def run
        Utils::GemSetup.setup_gem_environment!
        ENV["PATH"] = (ENV.fetch("PATH").split(":") | ENV.fetch("HOMEBREW_PATH", "").split(":")).join(":")
        ENV["BUNDLE_WITH"] = Utils::GemSetup.valid_gem_groups.join(":")

        ohai "cd #{HOMEBREW_LIBRARY_PATH}"
        HOMEBREW_LIBRARY_PATH.cd do
          if args.update
            ohai "bundle update"
            run_bundle "update", *args.update

            unless args.no_commit?
              ohai "git add Gemfile.lock"
              system "git", "add", "Gemfile.lock"
            end
          end

          ohai "bundle install --standalone"
          run_bundle "install", "--standalone"

          require "bundler"
          definition = Bundler::Definition.build(Bundler.default_gemfile, Bundler.default_lockfile, false)
          # Bundler ships with Ruby, outside the directory hashed by Bootsnap.
          core_gem_names = definition.specs_for([:default])
                                     .filter_map { |spec| spec.name if spec.name != "bundler" }
                                     .sort
          bootsnap_gem_names = Homebrew::Bootsnap.core_gem_names.sort
          if core_gem_names != bootsnap_gem_names
            raise <<~EOS
              Bootsnap core gem list is out of date.
              Expected: #{core_gem_names.join(", ")}
              Actual: #{bootsnap_gem_names.join(", ")}
            EOS
          end

          if GitHub::Actions.env_set? && HOMEBREW_PREFIX.to_s == HOMEBREW_LINUX_DEFAULT_PREFIX &&
             SystemCommand.sudo_available?
            ohai "chmod +t -R /home/linuxbrew/"
            system "sudo", "chmod", "+t", "-R", "/home/linuxbrew/"
          end

          ohai "bundle pristine"
          run_bundle "pristine"

          ohai "bundle clean"
          run_bundle "clean"

          system "git", "add", "Gemfile.lock" unless args.no_commit?

          if args.non_bundler_gems?
            %w[
              mechanize
            ].each do |gem|
              (HOMEBREW_LIBRARY_PATH/"vendor/gems").cd do
                Pathname.glob("#{gem}-*/").each { |path| FileUtils.rm_r(path) }
              end
              ohai "gem install #{gem}"
              SystemCommand.safe_system "gem", "install", gem, "--install-dir", "vendor",
                                        "--no-document", "--no-wrappers", "--ignore-dependencies", "--force"
              (HOMEBREW_LIBRARY_PATH/"vendor/gems").cd do
                source = Pathname.glob("#{gem}-*/").first
                next unless source

                # We cannot use `#ln_sf` here because that has unintended consequences when
                # the symlink we want to create exists and points to an existing directory.
                FileUtils.rm_f gem
                FileUtils.ln_s source, gem
              end
            end
          end

          unless args.no_commit?
            ohai "git add vendor"
            system "git", "add", "vendor"

            Utils::Git.set_name_email!
            Utils::Git.setup_gpg!

            ohai "git commit"
            system "git", "commit", "--message", "brew vendor-gems: commit updates."
          end
        end
      end

      sig { params(args: String).void }
      def run_bundle(*args)
        SystemCommand.safe_system "bundle", *args
      end
    end
  end
end
