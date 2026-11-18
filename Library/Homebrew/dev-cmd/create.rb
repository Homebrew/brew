# typed: strict
# frozen_string_literal: true

require "api/env"
require "utils/editor"

require "formula"
require "formula_creator"
require "missing_formula"
require "cask/appcast"
require "cask/cache"
require "cask/cask_loader"
require "cask/token_generator"
require "downloadable"
require "unpack_strategy"

module Homebrew
  module DevCmd
    class Create < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate a formula or, with `--cask`, a cask for the downloadable file at <URL>
          and open it in the editor. Homebrew will attempt to automatically derive the
          formula name and version, but if it fails, you'll have to make your own template.
          The `wget` formula serves as a simple example. For the complete API, see:
          <https://docs.brew.sh/rubydoc/Formula>
        EOS
        switch "--autotools",
               description: "Create a basic template for an Autotools-style build."
        switch "--cabal",
               description: "Create a basic template for a Cabal build."
        switch "--cask",
               description: "Create a basic template for a cask."
        switch "--cmake",
               description: "Create a basic template for a CMake-style build."
        switch "--crystal",
               description: "Create a basic template for a Crystal build."
        switch "--go",
               description: "Create a basic template for a Go build."
        switch "--meson",
               description: "Create a basic template for a Meson-style build."
        switch "--node",
               description: "Create a basic template for a Node build."
        switch "--perl",
               description: "Create a basic template for a Perl build."
        switch "--python",
               description: "Create a basic template for a Python build."
        switch "--ruby",
               description: "Create a basic template for a Ruby build."
        switch "--rust",
               description: "Create a basic template for a Rust build."
        switch "--zig",
               description: "Create a basic template for a Zig build."
        switch "--no-fetch",
               description: "Homebrew will not download <URL> to the cache and will thus not add its SHA-256 " \
                            "to the formula for you, nor will it check the GitHub API for GitHub projects " \
                            "(to fill out its description and homepage)."
        switch "--HEAD",
               description: "Indicate that <URL> points to the package's repository rather than a file."
        flag   "--set-name=",
               description: "Explicitly set the <name> of the new formula or cask."
        flag   "--set-version=",
               description: "Explicitly set the <version> of the new formula or cask."
        flag   "--set-license=",
               description: "Explicitly set the <license> of the new formula."
        flag   "--tap=",
               description: "Generate the new formula within the given tap, specified as <user>`/`<repo>."
        switch "-f", "--force",
               description: "Ignore errors for disallowed formula names and names that shadow aliases."

        conflicts "--autotools", "--cabal", "--cmake", "--crystal", "--go", "--meson", "--node",
                  "--perl", "--python", "--ruby", "--rust", "--zig", "--cask"
        conflicts "--cask", "--HEAD"
        conflicts "--cask", "--set-license"

        named_args :url, number: 1
      end

      # Create a formula from a tarball URL.
      sig { override.void }
      def run
        if args.cask?
          url = args.named.fetch(0)
          set_name = args.set_name&.strip
          name = if set_name.blank?
            stem = Pathname.new(url).stem.rpartition("=").last
            print "Cask name [#{stem}]: "
            __gets || stem
          else
            set_name
          end
          token = Cask::Utils.token_from(name)
          Cask::TokenGenerator.warnings(token).each { |warning| opoo warning }

          cask_tap = Tap.fetch(args.tap || "homebrew/cask")
          raise TapUnavailableError, cask_tap.name unless cask_tap.installed?

          path = cask_tap.new_cask_path(token)
          path.dirname.mkpath unless path.dirname.exist?
          raise Cask::CaskAlreadyCreatedError, token if path.exist?

          set_version = args.set_version
          version = if set_version
            Version.new(set_version)
          else
            Version.detect(url.gsub(token, "").gsub(/x86(?:_64)?/, ""))
          end

          interpolated_url, sha256 = if version.null?
            [url, ""]
          else
            sha256 = if args.no_fetch?
              ""
            else
              strategy = DownloadStrategyDetector.detect(url)
              downloader = strategy.new(url, token, version.to_s, cache: Cask::Cache.path)
              downloader.fetch
              download = downloader.cached_location
              Downloadable.verification_cache.sha256(download)
            end

            [url.gsub(version.to_s, "\#{version}"), sha256]
          end

          app, appcast = find_app_in(download) if download
          installed_app = Pathname("/Applications")/(app&.basename || "#{name}.app")
          appcast ||= find_appcast_for(installed_app)
          livecheck_url = appcast ? appcast.url.inspect : "\"\""
          livecheck_strategy = appcast ? appcast.strategy.inspect : "\"\""
          zap_comment, zap = if (generated_zap = generate_zap_for(installed_app))
            ["Check that each path belongs to the app.", generated_zap.gsub("\n", "\n  ")]
          else
            ["Install and launch the app, then run `brew generate-zap #{token}`.", 'zap trash: ""']
          end

          path.atomic_write <<~RUBY
            # Documentation: https://docs.brew.sh/Cask-Cookbook
            # PLEASE REMOVE ALL GENERATED COMMENTS BEFORE SUBMITTING YOUR PULL REQUEST!
            cask "#{token}" do
              version "#{version}"
              sha256 "#{sha256}"

              url "#{interpolated_url}"
              name "#{name}"
              desc ""
              homepage ""

              # Documentation: https://docs.brew.sh/Brew-Livecheck
              livecheck do
                url #{livecheck_url}
                strategy #{livecheck_strategy}
              end

              depends_on macos: ""

              app "#{app}"

              # #{zap_comment}
              # Documentation: https://docs.brew.sh/Cask-Cookbook#zap-creation
              #{zap}
            end
          RUBY

          puts "Please run `brew audit --cask --new #{token}` before submitting, thanks."
        else
          mode = if args.autotools?
            :autotools
          elsif args.cmake?
            :cmake
          elsif args.crystal?
            :crystal
          elsif args.go?
            :go
          elsif args.cabal?
            :cabal
          elsif args.meson?
            :meson
          elsif args.node?
            :node
          elsif args.perl?
            :perl
          elsif args.python?
            :python
          elsif args.ruby?
            :ruby
          elsif args.rust?
            :rust
          elsif args.zig?
            :zig
          end

          formula_creator = FormulaCreator.new(
            url:     args.named.fetch(0),
            name:    args.set_name,
            version: args.set_version,
            tap:     args.tap,
            mode:,
            license: args.set_license,
            fetch:   !args.no_fetch?,
            head:    args.HEAD?,
          )

          # ask for confirmation if name wasn't passed explicitly
          if args.set_name.blank?
            print "Formula name [#{formula_creator.name}]: "
            confirmed_name = __gets
            formula_creator.name = confirmed_name if confirmed_name.present?
          end

          formula_creator.verify_tap_available!

          # Check for disallowed formula, or names that shadow aliases,
          # unless --force is specified.
          unless args.force?
            if (reason = MissingFormula.disallowed_reason(formula_creator.name))
              odie <<~EOS
                The formula '#{formula_creator.name}' is not allowed to be created.
                #{reason}
                If you really want to create this formula use `--force`.
              EOS
            end

            Homebrew::API.with_no_api_env do
              if Formula.aliases.include?(formula_creator.name)
                realname = Formulary.canonical_name(formula_creator.name)
                odie <<~EOS
                  The formula '#{realname}' is already aliased to '#{formula_creator.name}'.
                  Please check that you are not creating a duplicate.
                  To force creation use `--force`.
                EOS
              end
            end
          end

          path = formula_creator.write_formula!

          formula = Homebrew::API.with_no_api_env do
            CoreTap.instance.clear_cache
            Formula[formula_creator.name]
          end

          if args.python?
            Utils::GemSetup.install_bundler_gems!(groups: ["ast"])
            require "utils/pypi"
            PyPI.update_python_resources! formula, ignore_non_pypi_packages: true
          end

          puts <<~EOS
            Please audit and test formula before submitting:
              HOMEBREW_NO_INSTALL_FROM_API=1 brew audit --new #{formula_creator.name}
              HOMEBREW_NO_INSTALL_FROM_API=1 brew install --build-from-source --verbose --debug #{formula_creator.name}
              HOMEBREW_NO_INSTALL_FROM_API=1 brew test #{formula_creator.name}
          EOS
        end

        Utils::Editor.open path
      end

      # Scan the app, from the download or an installed copy, for an appcast
      # to prefill the `livecheck` block.
      sig { params(app: Pathname).returns(T.nilable(Cask::Appcast::Result)) }
      def find_appcast_for(app)
        return unless app.directory?

        appcast = Cask::Appcast.find(app)
        ohai "Found #{appcast.strategy.inspect} appcast: #{appcast.url}" if appcast
        appcast
      end

      # Unpack the download to find the app it installs, relative to the
      # unpacked download, and that app's appcast. This only prefills the
      # template, so don't guess between the apps in a suite and warn rather
      # than fail if the download can't be unpacked.
      sig { params(download: Pathname).returns(T.nilable([Pathname, T.nilable(Cask::Appcast::Result)])) }
      def find_app_in(download)
        Dir.mktmpdir("brew-create", HOMEBREW_TEMP) do |dir|
          unpack_dir = Pathname(dir)
          UnpackStrategy.detect(download, merge_xattrs: true).extract_nestedly(to: unpack_dir)

          shallowest_apps = unpack_dir.glob("**/*.app").group_by { |app| app.each_filename.count }
                                      .min_by(&:first)&.last
          next unless shallowest_apps&.one?

          shallowest_app = shallowest_apps.fetch(0)
          [shallowest_app.relative_path_from(unpack_dir), find_appcast_for(shallowest_app)]
        end
      rescue => e
        opoo "Unable to unpack the download to find its app."
        odebug e.message
        nil
      end

      # Scan for files left by an already-installed copy of the app to prefill
      # the `zap` stanza.
      sig { params(app: Pathname).returns(T.nilable(String)) }
      def generate_zap_for(app)
        return unless app.directory?

        Utils.popen_read_text(HOMEBREW_BREW_FILE, "generate-zap", "--name", app.basename(".app").to_s, err: :err)
             .slice(/^zap (?:trash|delete):.*/m)&.chomp
      end

      private

      sig { returns(T.nilable(String)) }
      def __gets
        $stdin.gets&.presence&.chomp
      end
    end
  end
end
