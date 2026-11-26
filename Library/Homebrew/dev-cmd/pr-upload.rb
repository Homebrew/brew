# typed: strict
# frozen_string_literal: true

require "utils/brew_command"

require "abstract_command"
require "formula"
require "github_packages"
require "github_releases"
require "extend/hash/deep_merge"
require "bottle_transition"

module Homebrew
  module DevCmd
    class PrUpload < AbstractCommand
      cmd_args do
        description <<~EOS
          Apply the bottle commit and publish bottles to a host.
        EOS
        switch "--keep-old",
               description: "If the formula specifies a rebuild version, " \
                            "attempt to preserve its value in the generated DSL. " \
                            "When using GitHub Packages, this also appends the manifest to the existing list."
        switch "-n", "--dry-run",
               description: "Print what would be done rather than doing it."
        switch "--no-commit",
               description: "Do not generate a new commit before uploading."
        switch "--warn-on-upload-failure",
               description: "Warn instead of raising an error if the bottle upload fails. " \
                            "Useful for repairing bottle uploads that previously failed."
        switch "--upload-only",
               description: "Skip running `brew bottle` before uploading."
        flag   "--committer=",
               description: "Specify a committer name and email in `git`'s standard author format.",
               odisabled:   true
        flag   "--root-url=",
               description: "Use the specified <URL> as the root of the bottle's URL instead of Homebrew's default."
        flag   "--root-url-using=",
               description: "Use the specified download strategy class for downloading the bottle's URL instead of " \
                            "Homebrew's default."

        conflicts "--upload-only", "--no-commit"

        named_args :none

        hide_from_man_page!
      end

      sig { override.void }
      def run
        json_files = Dir["*.bottle.json"]
        odie "No bottle JSON files found in the current working directory" if json_files.blank?

        Utils::GemSetup.install_bundler_gems!(groups: ["pr_upload"])

        bottles_hash = bottles_hash_from_json_files(json_files, args)
        unbottled_formulae = T.let([], T::Array[String])

        unless args.upload_only?
          bottle_args = ["bottle", "--merge", "--write"]
          bottle_args << "--verbose" if args.verbose?
          bottle_args << "--debug" if args.debug?
          bottle_args << "--keep-old" if args.keep_old?
          bottle_args << "--root-url=#{args.root_url}" if args.root_url
          # A GitHub Packages bottle block is committed below, once it has its `manifest_sha256`.
          bottle_args << "--no-commit" if args.no_commit? || github_packages?(bottles_hash)
          bottle_args << "--root-url-using=#{args.root_url_using}" if args.root_url_using
          bottle_args += json_files

          if args.dry_run?
            dry_run_service = if github_packages?(bottles_hash)
              # GitHub Packages has its own --dry-run handling.
              nil
            elsif github_releases?(bottles_hash)
              "GitHub Releases"
            else
              odie "Service specified by root_url is not recognized"
            end

            if dry_run_service
              puts <<~EOS
                brew #{bottle_args.join " "}
                Upload bottles described by these JSON files to #{dry_run_service}:
                  #{json_files.join("\n  ")}
              EOS
              return
            end
          end

          check_bottled_formulae!(bottles_hash)
          unbottled_formulae = bottles_hash.select do |_, bottle_hash|
            Formulary.from_path(HOMEBREW_REPOSITORY/bottle_hash.fetch("formula").fetch("path"))
                     .bottle_specification
                     .checksums
                     .empty?
          end.keys

          Utils::BrewCommand.run!(*bottle_args)

          json_files = Dir["*.bottle.json"]
          if json_files.blank?
            puts "No bottle JSON files after merge, no upload needed!"
            return
          end

          # Reload the JSON files (in case `brew bottle --merge` generated
          # `all: $SHA256` bottles)
          bottles_hash = bottles_hash_from_json_files(json_files, args)
        end

        if github_releases?(bottles_hash)
          check_bottle_commits!(bottles_hash)
          github_releases = GitHubReleases.new
          github_releases.upload_bottles(bottles_hash)
        elsif github_packages?(bottles_hash)
          github_packages = GitHubPackages.new
          github_packages.upload_bottles(bottles_hash,
                                         keep_old:      args.keep_old?,
                                         dry_run:       args.dry_run?,
                                         warn_on_error: args.warn_on_upload_failure?) do |manifest_sha256s|
            pin_manifests!(bottles_hash, manifest_sha256s, unbottled_formulae)
            check_bottle_commits!(bottles_hash)
          end
        else
          odie "Service specified by root_url is not recognized"
        end
      end

      private

      # Writes the digest of the image index about to be uploaded into each
      # bottle block and commits it, so the block pins exactly what is uploaded.
      # A dry run does too: for GitHub Packages it has always written and
      # committed the bottle block and only left the registry untouched.
      sig {
        params(bottles_hash: T::Hash[String, T.untyped], manifest_sha256s: T::Hash[String, String],
               unbottled_formulae: T::Array[String]).void
      }
      def pin_manifests!(bottles_hash, manifest_sha256s, unbottled_formulae)
        bottles_hash.each do |formula_name, bottle_hash|
          path = HOMEBREW_REPOSITORY/bottle_hash.fetch("formula").fetch("path")
          manifest_sha256 = manifest_sha256s[formula_name]

          if args.upload_only?
            # No image is built for a formula whose upload is skipped, e.g. as it is already uploaded.
            pinned_sha256 = Utils::Bottles.formula_from_bottle_metadata(
              formula_name, bottle_hash.fetch("formula").fetch("path")
            ).bottle_specification.manifest_sha256
            next if pinned_sha256.nil? || manifest_sha256.nil? || pinned_sha256 == manifest_sha256

            odie "#{formula_name}: bottle block pins manifest #{pinned_sha256} " \
                 "but #{manifest_sha256} would be uploaded!"
          end

          if manifest_sha256
            # The first `sha256` line of the block `brew bottle --merge --write` just wrote.
            path.atomic_write(path.read.sub(/^( *)bottle do\n(?:(?! *sha256 ).*\n)*/) do |block_start|
              "#{block_start}#{Regexp.last_match(1)}  manifest_sha256 \"#{manifest_sha256}\"\n"
            end)
          end
          next if args.no_commit?

          Utils::Git.set_name_email!
          Utils::Git.setup_gpg!
          path.parent.cd do
            action = unbottled_formulae.include?(formula_name) ? "add" : "update"
            version = bottle_hash.fetch("formula").fetch("pkg_version")
            SystemCommand.safe_system "git", "commit", "--no-edit", "--verbose",
                                      "--message=#{Utils.name_from_full_name(formula_name)}: " \
                                      "#{action} #{version} bottle.",
                                      "--", path
          end
        end
      end

      sig { params(bottles_hash: T::Hash[String, T.untyped]).void }
      def check_bottle_commits!(bottles_hash)
        # Check the bottle commits did not break `brew audit`
        if !args.upload_only? && !args.no_commit?
          audit_args = ["audit", "--skip-style"]
          audit_args << "--verbose" if args.verbose?
          audit_args << "--debug" if args.debug?
          audit_args += bottles_hash.keys
          Utils::BrewCommand.run!(*audit_args)
        end

        check_transition_bottles!(bottles_hash)
      end

      sig { params(bottles_hash: T::Hash[String, T.untyped]).void }
      def check_transition_bottles!(bottles_hash)
        # Reload the bottle block written by `brew bottle --merge`.
        Formulary.clear_cache
        transition = BottleTransition.new
        bottles_hash.each do |name, bottle_hash|
          formula = Utils::Bottles.formula_from_bottle_metadata(name, bottle_hash.fetch("formula").fetch("path"))
          next unless transition.required?(formula)

          spec = formula.bottle_specification
          transition.check!(formula, tags: spec.collector.tags)
          bottle = bottle_hash.fetch("bottle")
          tags = bottle.fetch("tags").keys.map { |tag| Utils::Bottles.tag(tag.to_sym) }
          if !args.keep_old? && tags.exclude?(BottleTransition.tag) && tags.exclude?(Utils::Bottles.tag(:all))
            raise UsageError, <<~EOS
              #{formula.full_name} #{formula.pkg_version}: upload set is missing
              #{BottleTransition.tag} or `all` bottle artifacts.
              Restore the matching bottle artifacts and JSON files before retrying.
            EOS
          end

          root_url = bottle.fetch("root_url")
          metadata_matches = bottle_hash.fetch("formula").fetch("pkg_version") == formula.pkg_version.to_s &&
                             bottle.fetch("rebuild", 0).to_i == spec.rebuild &&
                             (GitHubPackages.root_url_if_match(root_url) || root_url) == spec.root_url &&
                             bottle.fetch("tags").all? do |tag, tag_hash|
                               tag_spec = spec.collector.specification_for(Utils::Bottles.tag(tag.to_sym),
                                                                           no_older_versions: true)
                               tag_spec && tag_spec.checksum.hexdigest == tag_hash.fetch("sha256")
                             end
          next if metadata_matches

          raise UsageError, "#{formula.full_name}: bottle metadata does not match the committed formula."
        end
      end

      sig { params(bottles_hash: T::Hash[String, T.untyped]).void }
      def check_bottled_formulae!(bottles_hash)
        bottles_hash.each do |name, bottle_hash|
          formula_version = Utils::Bottles.formula_from_bottle_metadata(
            name, bottle_hash.fetch("formula").fetch("path")
          ).pkg_version
          bottle_version = PkgVersion.parse bottle_hash["formula"]["pkg_version"]
          next if formula_version == bottle_version

          odie "Bottles are for #{name} #{bottle_version} but formula is version #{formula_version}!"
        end
      end

      sig { params(bottles_hash: T::Hash[String, T.untyped]).returns(T::Boolean) }
      def github_releases?(bottles_hash)
        return @github_releases if @github_releases

        github_releases = bottles_hash.values.all? do |bottle_hash|
          root_url = bottle_hash["bottle"]["root_url"]
          url_match = root_url.match GitHubReleases::URL_REGEX
          _, _, _, tag = *url_match

          tag
        end
        @github_releases = T.let(github_releases, T.nilable(T::Boolean))
        github_releases
      end

      sig { params(bottles_hash: T::Hash[String, T.untyped]).returns(T::Boolean) }
      def github_packages?(bottles_hash)
        return @github_packages if @github_packages

        github_packages = bottles_hash.values.all? do |bottle_hash|
          bottle_hash["bottle"]["root_url"].match? GitHubPackages::URL_REGEX
        end
        @github_packages = T.let(github_packages, T.nilable(T::Boolean))
        github_packages
      end

      sig { params(json_files: T::Array[String], args: T.untyped).returns(T::Hash[String, T.untyped]) }
      def bottles_hash_from_json_files(json_files, args)
        puts "Reading JSON files: #{json_files.join(", ")}" if args.verbose?

        bottles_hash = json_files.reduce({}) do |hash, json_file|
          incoming = JSON.parse(File.read(json_file))
          incoming.each do |name, bottle_hash|
            bottle = bottle_hash.fetch("bottle")
            bottle["root_url"] = GitHubPackages.root_url_if_match(bottle["root_url"]) || bottle["root_url"]
            previous = hash[name]
            next unless previous
            next if previous.fetch("formula").slice("path", "pkg_version") ==
                    bottle_hash.fetch("formula").slice("path", "pkg_version") &&
                    previous.fetch("bottle").slice("root_url", "rebuild") ==
                    bottle_hash.fetch("bottle").slice("root_url", "rebuild")

            raise UsageError, "Inconsistent bottle metadata for #{name} in #{json_file}."
          end
          hash.deep_merge(incoming)
        end

        if args.root_url
          bottles_hash.each_value do |bottle_hash|
            bottle_hash["bottle"]["root_url"] = args.root_url
          end
        end

        bottles_hash
      end
    end
  end
end
