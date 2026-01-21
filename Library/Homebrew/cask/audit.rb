# typed: strict
# frozen_string_literal: true

require "cask/denylist"
require "cask/download"
require "cask/installer"
require "cask/quarantine"
require "digest"
require "livecheck/livecheck"
require "source_location"
require "system_command"
require "utils/backtrace"
require "formula_name_cask_token_auditor"
require "utils/curl"
require "utils/git"
require "utils/shared_audits"
require "utils/output"

module Cask
  # Audit a cask for various problems.
  class Audit
    include SystemCommand::Mixin
    include ::Utils::Curl
    include ::Utils::Output::Mixin

    Error = T.type_alias do
      {
        message:   T.nilable(String),
        location:  T.nilable(Homebrew::SourceLocation),
        corrected: T::Boolean,
      }
    end

    sig { returns(Cask) }
    attr_reader :cask

    sig { returns(T.nilable(Download)) }
    attr_reader :download

    sig {
      params(
        cask: ::Cask::Cask, download: T::Boolean, quarantine: T::Boolean,
        online: T.nilable(T::Boolean), strict: T.nilable(T::Boolean), signing: T.nilable(T::Boolean),
        new_cask: T.nilable(T::Boolean), only: T::Array[String], except: T::Array[String]
      ).void
    }
    def initialize(
      cask,
      download: false, quarantine: false,
      online: nil, strict: nil, signing: nil,
      new_cask: nil, only: [], except: []
    )
      # `new_cask` implies `online`, `strict` and `signing`
      online = new_cask if online.nil?
      strict = new_cask if strict.nil?
      signing = new_cask if signing.nil?

      # `online` and `signing` imply `download`
      download ||= online || signing

      @cask = cask
      @download = T.let(nil, T.nilable(Download))
      @download = Download.new(cask, quarantine:) if download
      @online = online
      @strict = strict
      @signing = signing
      @new_cask = new_cask
      @only = only
      @except = except
      @livecheck_result = T.let(nil, T.nilable(T.any(T::Boolean, Symbol)))
    end

    sig { returns(T::Boolean) }
    def new_cask? = !!@new_cask

    sig { returns(T::Boolean) }
    def online? =!!@online

    sig { returns(T::Boolean) }
    def signing? = !!@signing

    sig { returns(T::Boolean) }
    def strict? = !!@strict

    sig { returns(::Cask::Audit) }
    def run!
      only_audits = @only
      except_audits = @except

      private_methods.map(&:to_s).grep(/^audit_/).each do |audit_method_name|
        name = audit_method_name.delete_prefix("audit_")
        next if !only_audits.empty? && only_audits.exclude?(name)
        next if except_audits.include?(name)

        send(audit_method_name)
      end

      self
    rescue => e
      odebug e, ::Utils::Backtrace.clean(e)
      add_error "exception while auditing #{cask}: #{e.message}"
      self
    end

    sig { returns(T::Array[Error]) }
    def errors
      @errors ||= T.let([], T.nilable(T::Array[Error]))
    end

    sig { returns(T::Boolean) }
    def errors?
      errors.any?
    end

    sig { returns(T::Boolean) }
    def success?
      !errors?
    end

    sig {
      params(
        message:     T.nilable(String),
        location:    T.nilable(Homebrew::SourceLocation),
        strict_only: T::Boolean,
      ).void
    }
    def add_error(message, location: nil, strict_only: false)
      # Only raise non-critical audits if the user specified `--strict`.
      return if strict_only && !@strict

      errors << { message:, location:, corrected: false }
    end

    sig { returns(T.nilable(String)) }
    def result
      Formatter.error("failed") if errors?
    end

    sig { returns(T.nilable(String)) }
    def summary
      return if success?

      summary = ["audit for #{cask}: #{result}"]

      errors.each do |error|
        summary << " #{Formatter.error("-")} #{error[:message]}"
      end

      summary.join("\n")
    end

    private

    sig { void }
    def audit_untrusted_pkg
      odebug "Auditing pkg stanza: allow_untrusted"

      return if @cask.sourcefile_path.nil?

      tap = @cask.tap
      return if tap.nil?
      return if tap.user != "Homebrew"

      return if cask.artifacts.none? { |k| k.is_a?(Artifact::Pkg) && k.stanza_options.key?(:allow_untrusted) }

      add_error "allow_untrusted is not permitted in official Homebrew Cask taps"
    end

    sig { void }
    def audit_stanza_requires_uninstall
      odebug "Auditing stanzas which require an uninstall"

      return if cask.artifacts.none? { |k| k.is_a?(Artifact::Pkg) || k.is_a?(Artifact::Installer) }
      return if cask.artifacts.any?(Artifact::Uninstall)

      add_error "installer and pkg stanzas require an uninstall stanza"
    end

    sig { void }
    def audit_single_pre_postflight
      odebug "Auditing preflight and postflight stanzas"

      if cask.artifacts.count { |k| k.is_a?(Artifact::PreflightBlock) && k.directives.key?(:preflight) } > 1
        add_error "only a single preflight stanza is allowed"
      end

      count = cask.artifacts.count do |k|
        k.is_a?(Artifact::PostflightBlock) &&
          k.directives.key?(:postflight)
      end
      return if count <= 1

      add_error "only a single postflight stanza is allowed"
    end

    sig { void }
    def audit_single_uninstall_zap
      odebug "Auditing single uninstall_* and zap stanzas"

      count = cask.artifacts.count do |k|
        k.is_a?(Artifact::PreflightBlock) &&
          k.directives.key?(:uninstall_preflight)
      end

      add_error "only a single uninstall_preflight stanza is allowed" if count > 1

      count = cask.artifacts.count do |k|
        k.is_a?(Artifact::PostflightBlock) &&
          k.directives.key?(:uninstall_postflight)
      end

      add_error "only a single uninstall_postflight stanza is allowed" if count > 1

      return if cask.artifacts.count { |k| k.is_a?(Artifact::Zap) } <= 1

      add_error "only a single zap stanza is allowed"
    end

    sig { void }
    def audit_required_stanzas
      odebug "Auditing required stanzas"
      [:version, :sha256, :url, :homepage].each do |sym|
        add_error "a #{sym} stanza is required" unless cask.send(sym)
      end
      add_error "at least one name stanza is required" if cask.name.empty?
      # TODO: specific DSL knowledge should not be spread around in various files like this
      rejected_artifacts = [:uninstall, :zap]
      installable_artifacts = cask.artifacts.reject { |k| rejected_artifacts.include?(k) }
      add_error "at least one activatable artifact stanza is required" if installable_artifacts.empty?
    end

    sig { void }
    def audit_description
      # Fonts seldom benefit from descriptions and requiring them disproportionately
      # increases the maintenance burden.
      return if cask.tap == "homebrew/cask" && cask.token.include?("font-")

      add_error("Cask should have a description. Please add a `desc` stanza.", strict_only: true) if cask.desc.blank?
    end

    sig { void }
    def audit_version_special_characters
      return unless cask.version

      return if cask.version.latest?

      raw_version = cask.version.raw_version
      return if raw_version.exclude?(":") && raw_version.exclude?("/")

      add_error "version should not contain colons or slashes"
    end

    sig { void }
    def audit_no_string_version_latest
      return unless cask.version

      odebug "Auditing version :latest does not appear as a string ('latest')"
      return if cask.version.raw_version != "latest"

      add_error "you should use version :latest instead of version 'latest'"
    end

    sig { void }
    def audit_sha256_no_check_if_latest
      return unless cask.sha256
      return unless cask.version

      odebug "Auditing sha256 :no_check with version :latest"
      return unless cask.version.latest?
      return if cask.sha256 == :no_check

      add_error "you should use sha256 :no_check when version is :latest"
    end

    sig { void }
    def audit_sha256_no_check_if_unversioned
      return unless cask.sha256
      return if cask.sha256 == :no_check

      return unless cask.url&.unversioned?

      add_error "Use `sha256 :no_check` when URL is unversioned."
    end

    sig { void }
    def audit_sha256_actually_256
      return unless cask.sha256

      odebug "Auditing sha256 string is a legal SHA-256 digest"
      return unless cask.sha256.is_a?(Checksum)
      return if cask.sha256.length == 64 && cask.sha256[/^[0-9a-f]+$/i]

      add_error "sha256 string must be of 64 hexadecimal characters"
    end

    sig { void }
    def audit_sha256_invalid
      return unless cask.sha256

      odebug "Auditing sha256 is not a known invalid value"
      empty_sha256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      return if cask.sha256 != empty_sha256

      add_error "cannot use the sha256 for an empty string: #{empty_sha256}"
    end

    sig { void }
    def audit_latest_with_livecheck
      return unless cask.version&.latest?
      return unless cask.livecheck_defined?
      return if cask.livecheck.skip?

      add_error "Casks with a `livecheck` should not use `version :latest`."
    end

    sig { void }
    def audit_latest_with_auto_updates
      return unless cask.version&.latest?
      return unless cask.auto_updates

      add_error "Casks with `version :latest` should not use `auto_updates`."
    end

    LIVECHECK_REFERENCE_URL = "https://docs.brew.sh/Cask-Cookbook#stanza-livecheck"
    private_constant :LIVECHECK_REFERENCE_URL

    sig { void }
    def audit_hosting_with_livecheck
      return if cask.deprecated? || cask.disabled?
      return if cask.version&.latest?
      return if (url = cask.url).nil?
      return if cask.livecheck_defined?
      return if audit_livecheck_version == :auto_detected

      add_livecheck = "please add a livecheck. See #{Formatter.url(LIVECHECK_REFERENCE_URL)}"

      case url.to_s
      when %r{sourceforge.net/(\S+)}
        return unless online?

        add_error "Download is hosted on SourceForge, #{add_livecheck}", location: url.location
      when %r{dl.devmate.com/(\S+)}
        add_error "Download is hosted on DevMate, #{add_livecheck}", location: url.location
      when %r{rink.hockeyapp.net/(\S+)}
        add_error "Download is hosted on HockeyApp, #{add_livecheck}", location: url.location
      end
    end

    SOURCEFORGE_OSDN_REFERENCE_URL = "https://docs.brew.sh/Cask-Cookbook#sourceforgeosdn-urls"
    private_constant :SOURCEFORGE_OSDN_REFERENCE_URL

    sig { void }
    def audit_download_url_format
      return if (url = cask.url).nil?

      odebug "Auditing URL format"
      return unless bad_sourceforge_url?

      add_error "SourceForge URL format incorrect. See #{Formatter.url(SOURCEFORGE_OSDN_REFERENCE_URL)}",
                location: url.location
    end

    sig { void }
    def audit_download_url_is_osdn
      return if (url = cask.url).nil?
      return unless bad_osdn_url?

      add_error "OSDN download urls are disabled.", location: url.location, strict_only: true
    end

    VERIFIED_URL_REFERENCE_URL = "https://docs.brew.sh/Cask-Cookbook#when-url-and-homepage-domains-differ-add-verified"
    private_constant :VERIFIED_URL_REFERENCE_URL

    sig { void }
    def audit_unnecessary_verified
      return unless cask.url
      return unless verified_present?
      return unless url_match_homepage?
      return unless verified_matches_url?

      add_error "The URL's domain #{Formatter.url(domain)} matches the homepage domain " \
                "#{Formatter.url(homepage)}, the 'verified' parameter of the 'url' stanza is unnecessary. " \
                "See #{Formatter.url(VERIFIED_URL_REFERENCE_URL)}"
    end

    sig { void }
    def audit_missing_verified
      return unless cask.url
      return if file_url?
      return if url_match_homepage?
      return if verified_present?

      add_error "The URL's domain #{Formatter.url(domain)} does not match the homepage domain " \
                "#{Formatter.url(homepage)}, a 'verified' parameter has to be added to the 'url' stanza. " \
                "See #{Formatter.url(VERIFIED_URL_REFERENCE_URL)}"
    end

    sig { void }
    def audit_no_match
      return if (url = cask.url).nil?
      return unless verified_present?
      return if verified_matches_url?

      add_error "Verified URL #{Formatter.url(url_from_verified)} does not match URL " \
                "#{Formatter.url(strip_url_scheme(url.to_s))}. " \
                "See #{Formatter.url(VERIFIED_URL_REFERENCE_URL)}",
                location: url.location
    end

    sig { void }
    def audit_generic_artifacts
      cask.artifacts.select { |a| a.is_a?(Artifact::Artifact) }.each do |artifact|
        unless artifact.target.absolute?
          add_error "target must be absolute path for #{artifact.class.english_name} #{artifact.source}"
        end
      end
    end

    sig { void }
    def audit_languages
      @cask.languages.each do |language|
        Locale.parse(language)
      rescue Locale::ParserError
        add_error "Locale '#{language}' is invalid."
      end
    end

    sig { void }
    def audit_token
      token_auditor = Homebrew::FormulaNameCaskTokenAuditor.new(cask.token)
      return if (errors = token_auditor.errors).none?

      add_error "Cask token '#{cask.token}' must not contain #{errors.to_sentence(two_words_connector: " or ",
                                                                                  last_word_connector: " or ")}."
    end

    sig { void }
    def audit_token_conflicts
      Homebrew.with_no_api_env do
        return unless core_formula_names.include?(cask.token)

        add_error("cask token conflicts with an existing homebrew/core formula: #{Formatter.url(core_formula_url)}")
      end
    end

    sig { void }
    def audit_token_bad_words
      return unless new_cask?

      token = cask.token

      add_error "cask token contains .app" if token.end_with? ".app"

      match_data = /-(?<designation>alpha|beta|rc|release-candidate)$/.match(cask.token)
      if match_data && cask.tap&.official?
        add_error "cask token contains version designation '#{match_data[:designation]}'"
      end

      add_error("cask token mentions launcher", strict_only: true) if token.end_with? "launcher"

      add_error("cask token mentions desktop", strict_only: true) if token.end_with? "desktop"

      add_error("cask token mentions platform", strict_only: true) if token.end_with? "mac", "osx", "macos"

      add_error("cask token mentions architecture", strict_only: true) if token.end_with? "x86", "32_bit", "x86_64",
                                                                                          "64_bit"

      frameworks = %w[cocoa qt gtk wx java]
      return if frameworks.include?(token) || !token.end_with?(*frameworks)

      add_error("cask token mentions framework", strict_only: true)
    end

    sig { void }
    def audit_download
      return if (download = self.download).blank? || (url = cask.url).nil?

      begin
        download.fetch
      rescue => e
        add_error "download not possible: #{e}", location: url.location
      end
    end

    sig { void }
    def audit_livecheck_unneeded_long_version
      return if cask.version.nil? || (url = cask.url).nil?
      return if cask.livecheck.strategy != :sparkle
      return unless cask.version.csv.second
      return if cask.url.to_s.include? cask.version.csv.second
      return if cask.version.csv.third.present? && cask.url.to_s.include?(cask.version.csv.third)

      add_error "Download does not require additional version components. Use `&:short_version` in the livecheck",
                location:    url.location,
                strict_only: true
    end

    sig { void }
    def audit_signing
      return if download.blank?

      url = cask.url
      return if url.nil?

      return if !cask.tap.official? && !signing?
      return if cask.deprecated? && cask.deprecation_reason != :fails_gatekeeper_check

      unless Quarantine.available?
        odebug "Quarantine support is not available, skipping signing audit"
        return
      end

      odebug "Auditing signing"
      is_in_skiplist = cask.tap&.audit_exception(:signing_audit_skiplist, cask.token,
                                                 Homebrew::SimulateSystem.current_arch.to_s) ||
                       cask.tap&.audit_exception(:signing_audit_skiplist, cask.token, "all")

      extract_artifacts do |artifacts, tmpdir|
        is_container = artifacts.any? { |a| a.is_a?(Artifact::App) || a.is_a?(Artifact::Pkg) }

        any_signing_failure = artifacts.any? do |artifact|
          next false if artifact.is_a?(Artifact::Binary) && is_container == true

          artifact_path = artifact.is_a?(Artifact::Pkg) ? artifact.path : artifact.source

          path = tmpdir/artifact_path.relative_path_from(cask.staged_path)

          unless Quarantine.detect(path)
            odebug "#{path} does not have quarantine attributes, skipping signing audit"
            next false
          end

          result = case artifact
          when Artifact::Pkg
            system_command("spctl", args: ["--assess", "--type", "install", path], print_stderr: false)
          when Artifact::App
            next opoo "gktool not found, skipping app signing audit" unless which("gktool")

            system_command("gktool", args: ["scan", path], print_stderr: false)
          when Artifact::Binary
            # Shell scripts cannot be signed, so we skip them
            next false if path.text_executable?

            system_command("codesign", args:         ["--verify", "-R=notarized", "--check-notarization", path],
                                       print_stderr: false)
          else
            add_error "Unknown artifact type: #{artifact.class}", location: url.location
            next
          end

          next false if result.success?
          next true if cask.deprecated? && cask.deprecation_reason == :fails_gatekeeper_check
          next true if is_in_skiplist

          signing_failure_message = <<~EOS
            Signature verification failed:
            #{result.merged_output}
          EOS

          if cask.tap.official?
            signing_failure_message += <<~EOS
              The homebrew/cask tap requires all casks to be signed and notarized by Apple.
              Please contact the upstream developer and ask them to sign and notarize their software.
            EOS
          end

          add_error signing_failure_message

          true
        end

        return if any_signing_failure

        add_error "Cask is in the signing audit skiplist, but does not need to be skipped!" if is_in_skiplist

        return unless cask.deprecated?
        return if cask.deprecation_reason != :fails_gatekeeper_check

        add_error <<~EOS
          Cask is deprecated because it failed Gatekeeper checks but all artifacts now pass!
          Remove the deprecate/disable stanza or update the deprecate/disable reason.
        EOS
      end
    end

    sig {
      params(
        _block: T.nilable(T.proc.params(
          arg0: T::Array[T.any(Artifact::Pkg, Artifact::Relocated)],
          arg1: Pathname,
        ).void),
      ).void
    }
    def extract_artifacts(&_block)
      return unless online?
      return if (download = self.download).nil?

      artifacts = cask.artifacts.select do |artifact|
        artifact.is_a?(Artifact::Pkg) || artifact.is_a?(Artifact::App) || artifact.is_a?(Artifact::Binary)
      end

      if @artifacts_extracted && @tmpdir
        yield artifacts, @tmpdir if block_given?
        return
      end

      return if artifacts.empty?

      @tmpdir ||= T.let(Pathname(Dir.mktmpdir("cask-audit", HOMEBREW_TEMP)), T.nilable(Pathname))

      # Clean up tmp dir when @tmpdir object is destroyed
      ObjectSpace.define_finalizer(
        @tmpdir,
        proc { FileUtils.remove_entry(@tmpdir) },
      )

      ohai "Downloading and extracting artifacts"

      downloaded_path = download.fetch

      primary_container = UnpackStrategy.detect(downloaded_path, type: @cask.container&.type, merge_xattrs: true)
      return if primary_container.nil?

      # If the container has any dependencies we need to install them or unpacking will fail.
      if primary_container.dependencies.any?

        install_options = {
          show_header:             true,
          installed_as_dependency: true,
          installed_on_request:    false,
          verbose:                 false,
        }.compact

        Homebrew::Install.perform_preinstall_checks_once
        formula_installers = primary_container.dependencies.filter_map do |dep|
          next unless dep.is_a?(Formula)

          FormulaInstaller.new(
            dep,
            **install_options,
          )
        end
        valid_formula_installers = Homebrew::Install.fetch_formulae(formula_installers)

        formula_installers.each do |fi|
          next unless valid_formula_installers.include?(fi)

          fi.install
          fi.finish
        end
      end

      # Extract the container to the temporary directory.
      primary_container.extract_nestedly(to: @tmpdir, basename: downloaded_path.basename, verbose: false)

      if (nested_container = @cask.container&.nested)
        FileUtils.chmod_R "+rw", @tmpdir/nested_container, force: true, verbose: false
        UnpackStrategy.detect(@tmpdir/nested_container, merge_xattrs: true)
                      .extract_nestedly(to: @tmpdir, verbose: false)
      end

      # Process rename operations after extraction
      # Create a temporary installer to process renames in the audit directory
      temp_installer = Installer.new(@cask)
      temp_installer.process_rename_operations(target_dir: @tmpdir)

      # Set the flag to indicate that extraction has occurred.
      @artifacts_extracted = T.let(true, T.nilable(TrueClass))

      # Yield the artifacts and temp directory to the block if provided.
      yield artifacts, @tmpdir if block_given?
    end

    sig { void }
    def audit_rosetta
      return if (url = cask.url).nil?
      return unless online?
      # Rosetta 2 is only for ARM-capable macOS versions, which are Big Sur (11.x) and later
      return if Homebrew::SimulateSystem.current_arch != :arm
      return if MacOSVersion::SYMBOLS.fetch(Homebrew::SimulateSystem.current_os, "10") < "11"
      return if cask.depends_on.macos&.maximum_version.to_s < "11"

      odebug "Auditing Rosetta 2 requirement"

      extract_artifacts do |artifacts, tmpdir|
        is_container = artifacts.any? { |a| a.is_a?(Artifact::App) || a.is_a?(Artifact::Pkg) }

        mentions_rosetta = cask.caveats.include?("requires Rosetta 2")
        requires_intel = cask.depends_on.arch&.any? { |arch| arch[:type] == :intel }

        artifacts_to_test = artifacts.filter do |artifact|
          next false if !artifact.is_a?(Artifact::App) && !artifact.is_a?(Artifact::Binary)
          next false if artifact.is_a?(Artifact::Binary) && is_container

          true
        end

        next if artifacts_to_test.blank?

        any_requires_rosetta = artifacts_to_test.any? do |artifact|
          artifact = T.cast(artifact, T.any(Artifact::App, Artifact::Binary))
          path = tmpdir/artifact.source.relative_path_from(cask.staged_path)

          result = case artifact
          when Artifact::App
            files = Dir[path/"Contents/MacOS/*"].select do |f|
              File.executable?(f) && !File.directory?(f) && !f.end_with?(".dylib")
            end
            add_error "No binaries in App: #{artifact.source}", location: url.location if files.empty?

            main_binary = get_plist_main_binary(path)
            main_binary ||= files.fetch(0)

            system_command("lipo", args: ["-archs", main_binary], print_stderr: false)
          when Artifact::Binary
            binary_path = path.to_s.gsub(cask.appdir, tmpdir.to_s)
            system_command("lipo", args: ["-archs", binary_path], print_stderr: true)
          else
            T.absurd(artifact)
          end

          # binary stanza can contain shell scripts, so we just continue if lipo fails.
          next false unless result.success?

          odebug "Architectures: #{result.merged_output}"

          unless /arm64|x86_64/.match?(result.merged_output)
            add_error "Artifacts architecture is no longer supported by macOS!",
                      location: url.location
            next
          end

          result.merged_output.exclude?("arm64") && result.merged_output.include?("x86_64")
        end

        if any_requires_rosetta
          if !mentions_rosetta && !requires_intel
            add_error "At least one artifact requires Rosetta 2 but this is not indicated by the caveats!",
                      location: url.location
          end
        elsif mentions_rosetta
          add_error "No artifacts require Rosetta 2 but the caveats say otherwise!",
                    location: url.location
        end
      end
    end

    sig { returns(T.nilable(T.any(T::Boolean, Symbol))) }
    def audit_livecheck_version
      return @livecheck_result unless @livecheck_result.nil?
      return unless online?
      return unless cask.version

      odebug "Auditing livecheck version"

      referenced_cask, = Homebrew::Livecheck.resolve_livecheck_reference(cask)

      # Respect skip conditions for a referenced cask
      if referenced_cask
        skip_info = Homebrew::Livecheck::SkipConditions.referenced_skip_information(
          referenced_cask,
          Homebrew::Livecheck.package_or_resource_name(cask),
        )
      end

      # Respect cask skip conditions (e.g. deprecated, disabled, latest, unversioned)
      skip_info ||= Homebrew::Livecheck::SkipConditions.skip_information(cask)
      if skip_info.present?
        @livecheck_result = :skip
        return @livecheck_result
      end

      latest_version = Homebrew::Livecheck.latest_version(
        cask,
        referenced_formula_or_cask: referenced_cask,
      )&.fetch(:latest, nil)

      if latest_version && (cask.version.to_s == latest_version.to_s)
        @livecheck_result = :auto_detected
        return @livecheck_result
      end

      add_error "Version '#{cask.version}' differs from '#{latest_version}' retrieved by livecheck."

      @livecheck_result = false
    end

    sig { void }
    def audit_min_os
      return unless online?

      odebug "Auditing minimum macOS version"

      bundle_min_os = cask_bundle_min_os
      sparkle_min_os = cask_sparkle_min_os

      app_min_os = bundle_min_os || sparkle_min_os
      debug_messages = []
      debug_messages << "from artifact: #{bundle_min_os.to_sym}" if bundle_min_os
      debug_messages << "from upstream: #{sparkle_min_os.to_sym}" if sparkle_min_os
      odebug "Detected minimum macOS: #{app_min_os.to_sym} (#{debug_messages.join(" | ")})" if app_min_os
      return if app_min_os.nil? || app_min_os <= HOMEBREW_MACOS_OLDEST_ALLOWED

      on_system_block_min_os = cask.on_system_block_min_os
      depends_on_min_os = cask.depends_on.macos&.minimum_version

      cask_min_os = [on_system_block_min_os, depends_on_min_os].compact.max
      debug_messages = []
      debug_messages << "from on_system block: #{on_system_block_min_os.to_sym}" if on_system_block_min_os
      if depends_on_min_os > HOMEBREW_MACOS_OLDEST_ALLOWED
        debug_messages << "from depends_on stanza: #{depends_on_min_os.to_sym}"
      end
      odebug "Declared minimum macOS: #{cask_min_os.to_sym} (#{debug_messages.join(" | ").presence || "default"})"
      return if cask_min_os.to_sym == app_min_os.to_sym
      # ignore declared minimum OS < 11.x when auditing as ARM a cask with arch-specific artifacts
      return if OnSystem.arch_condition_met?(:arm) &&
                cask.on_system_blocks_exist? &&
                cask_min_os.present? &&
                app_min_os < MacOSVersion.new("11") &&
                app_min_os < cask_min_os

      min_os_definition = if cask_min_os > HOMEBREW_MACOS_OLDEST_ALLOWED
        definition = if T.must(on_system_block_min_os.to_s <=> depends_on_min_os.to_s).positive?
          "an on_system block"
        else
          "a depends_on stanza"
        end
        "#{definition} with a minimum macOS version of #{cask_min_os.to_sym.inspect}"
      else
        "no minimum macOS version"
      end
      source = T.must(bundle_min_os.to_s <=> sparkle_min_os.to_s).positive? ? "Artifact" : "Upstream"
      add_error "#{source} defined #{app_min_os.to_sym.inspect} as the minimum macOS version " \
                "but the cask declared #{min_os_definition}"
    end

    sig { returns(T.nilable(MacOSVersion)) }
    def cask_sparkle_min_os
      return unless online?
      return unless cask.livecheck_defined?
      return if cask.livecheck.strategy != :sparkle

      # `Sparkle` strategy blocks that use the `items` argument (instead of
      # `item`) contain arbitrary logic that ignores/overrides the strategy's
      # sorting, so we can't identify which item would be first/newest here.
      return if cask.livecheck.strategy_block.present? &&
                cask.livecheck.strategy_block.parameters[0] == [:opt, :items]

      content = Homebrew::Livecheck::Strategy.page_content(cask.livecheck.url)[:content]
      return if content.blank?

      begin
        items = Homebrew::Livecheck::Strategy::Sparkle.sort_items(
          Homebrew::Livecheck::Strategy::Sparkle.filter_items(
            Homebrew::Livecheck::Strategy::Sparkle.items_from_content(content),
          ),
        )
      rescue
        return
      end
      return if items.blank?

      min_os = items[0]&.minimum_system_version&.strip_patch
      # Big Sur is sometimes identified as 10.16, so we override it to the
      # expected macOS version (11).
      min_os = MacOSVersion.new("11") if min_os == "10.16"
      min_os
    end

    sig { returns(T.nilable(MacOSVersion)) }
    def cask_bundle_min_os
      return unless online?

      min_os = T.let(nil, T.untyped)
      @staged_path ||= T.let(cask.staged_path, T.nilable(Pathname))

      extract_artifacts do |artifacts, tmpdir|
        artifacts.each do |artifact|
          artifact_path = artifact.is_a?(Artifact::Pkg) ? artifact.path : artifact.source
          path = tmpdir/artifact_path.relative_path_from(cask.staged_path)

          # Handle .pkg artifacts by expanding and checking Distribution file
          if artifact.is_a?(Artifact::Pkg)
            pkg_expanded_dir = tmpdir/"pkg-expanded"
            begin
              system_command!("pkgutil", args: ["--expand-full", path.to_s, pkg_expanded_dir.to_s])

              distribution_file = pkg_expanded_dir/"Distribution"
              if File.exist?(distribution_file)
                distribution_content = File.read(distribution_file)
                if (match = distribution_content.match(/<os-version\s+min="(?<version>[^"]+)"/))
                  min_os = match[:version]
                  break if min_os
                end
              end
            rescue
              break
            ensure
              FileUtils.remove_entry(pkg_expanded_dir) if pkg_expanded_dir.exist?
            end
          end

          info_plist_paths = Dir.glob("#{path}/**/Contents/Info.plist")

          # Ensure the main `Info.plist` file is checked first, as this can
          # sometimes use the min_os version from a framework instead
          if info_plist_paths.delete("#{path}/Contents/Info.plist")
            info_plist_paths.insert(0, "#{path}/Contents/Info.plist")
          end

          info_plist_paths.each do |plist_path|
            next unless File.exist?(plist_path)

            plist = system_command!("plutil", args: ["-convert", "xml1", "-o", "-", plist_path]).plist
            min_os = plist["LSMinimumSystemVersion"].presence
            break if min_os

            # Get the app bundle path from the plist path
            app_bundle_path = Pathname(plist_path).dirname.dirname
            next unless (main_binary = get_plist_main_binary(app_bundle_path))
            next if !File.exist?(main_binary) || File.open(main_binary, "rb") { |f| f.read(2) == "#!" }

            macho = MachO.open(main_binary)
            min_os = case macho
            when MachO::MachOFile
              [
                macho[:LC_VERSION_MIN_MACOSX].first&.version_string,
                macho[:LC_BUILD_VERSION].first&.minos_string,
              ]
            when MachO::FatFile
              # Collect requirements by architecture
              arch_min_os = { arm: [], intel: [] }
              macho.machos.each do |slice|
                macos_reqs = [
                  slice[:LC_VERSION_MIN_MACOSX].first&.version_string,
                  slice[:LC_BUILD_VERSION].first&.minos_string,
                ]

                case slice.cputype
                when *Hardware::CPU::ARM_ARCHS
                  arch_min_os[:arm].concat(macos_reqs)
                when *Hardware::CPU::INTEL_ARCHS
                  arch_min_os[:intel].concat(macos_reqs)
                end
              end

              # Only use the requirements for the current architecture
              arch_min_os.fetch(Homebrew::SimulateSystem.current_arch, [])
            end.compact.max
            break if min_os
          end
          break if min_os
        end
      end

      begin
        MacOSVersion.new(min_os).strip_patch
      rescue MacOSVersion::Error
        nil
      end
    end

    sig { params(path: Pathname).returns(T.nilable(String)) }
    def get_plist_main_binary(path)
      return unless online?

      plist_path = "#{path}/Contents/Info.plist"
      return unless File.exist?(plist_path)

      plist = system_command!("plutil", args: ["-convert", "xml1", "-o", "-", plist_path]).plist
      binary = plist["CFBundleExecutable"].presence
      return unless binary

      binary_path = "#{path}/Contents/MacOS/#{binary}"

      binary_path if File.exist?(binary_path) && File.executable?(binary_path)
    end

    sig { void }
    def audit_github_prerelease_version
      return if (url = cask.url).nil?

      odebug "Auditing GitHub prerelease"
      user, repo = get_repo_data(%r{https?://github\.com/([^/]+)/([^/]+)/?.*}) if online?
      return if user.nil? || repo.nil?

      tag = SharedAudits.github_tag_from_url(url.to_s)
      tag ||= cask.version
      error = SharedAudits.github_release(user, repo, tag, cask:)
      add_error error, location: url.location if error
    end

    sig { void }
    def audit_gitlab_prerelease_version
      return if (url = cask.url).nil?

      user, repo = get_repo_data(%r{https?://gitlab\.com/([^/]+)/([^/]+)/?.*}) if online?
      return if user.nil? || repo.nil?

      odebug "Auditing GitLab prerelease"

      tag = SharedAudits.gitlab_tag_from_url(url.to_s)
      tag ||= cask.version
      error = SharedAudits.gitlab_release(user, repo, tag, cask:)
      add_error error, location: url.location if error
    end

    sig { void }
    def audit_forgejo_prerelease_version
      return if (url = cask.url).nil?

      odebug "Auditing Forgejo prerelease"
      user, repo = get_repo_data(%r{https?://codeberg\.org/([^/]+)/([^/]+)/?.*}) if online?
      return if user.nil? || repo.nil?

      tag = SharedAudits.forgejo_tag_from_url(url.to_s)
      tag ||= cask.version
      error = SharedAudits.forgejo_release(user, repo, tag, cask:)
      add_error error, location: url.location if error
    end

    sig { void }
    def audit_github_repository_archived
      # Deprecated/disabled casks may have an archived repository.
      return if cask.deprecated? || cask.disabled?
      return if (url = cask.url).nil?

      user, repo = get_repo_data(%r{https?://github\.com/([^/]+)/([^/]+)/?.*}) if online?
      return if user.nil? || repo.nil?

      metadata = SharedAudits.github_repo_data(user, repo)
      return if metadata.nil?

      add_error "GitHub repo is archived", location: url.location if metadata["archived"]
    end

    sig { void }
    def audit_gitlab_repository_archived
      # Deprecated/disabled casks may have an archived repository.
      return if cask.deprecated? || cask.disabled?
      return if (url = cask.url).nil?

      user, repo = get_repo_data(%r{https?://gitlab\.com/([^/]+)/([^/]+)/?.*}) if online?
      return if user.nil? || repo.nil?

      odebug "Auditing GitLab repo archived"

      metadata = SharedAudits.gitlab_repo_data(user, repo)
      return if metadata.nil?

      add_error "GitLab repo is archived", location: url.location if metadata["archived"]
    end

    sig { void }
    def audit_forgejo_repository_archived
      return if cask.deprecated? || cask.disabled?
      return if (url = cask.url).nil?

      user, repo = get_repo_data(%r{https?://codeberg\.org/([^/]+)/([^/]+)/?.*}) if online?
      return if user.nil? || repo.nil?

      metadata = SharedAudits.forgejo_repo_data(user, repo)
      return if metadata.nil?

      return unless metadata["archived"]

      add_error "Forgejo repository is archived since #{metadata["archived_at"]}",
                location: url.location
    end

    sig { void }
    def audit_github_repository
      return unless new_cask?
      return if (url = cask.url).nil?

      user, repo = get_repo_data(%r{https?://github\.com/([^/]+)/([^/]+)/?.*})
      return if user.nil? || repo.nil?

      odebug "Auditing GitHub repo"

      error = SharedAudits.github(user, repo)
      add_error error, location: url.location if error
    end

    sig { void }
    def audit_gitlab_repository
      return unless new_cask?
      return if (url = cask.url).nil?

      user, repo = get_repo_data(%r{https?://gitlab\.com/([^/]+)/([^/]+)/?.*})
      return if user.nil? || repo.nil?

      odebug "Auditing GitLab repo"

      error = SharedAudits.gitlab(user, repo)
      add_error error, location: url.location if error
    end

    sig { void }
    def audit_bitbucket_repository
      return unless new_cask?
      return if (url = cask.url).nil?

      user, repo = get_repo_data(%r{https?://bitbucket\.org/([^/]+)/([^/]+)/?.*})
      return if user.nil? || repo.nil?

      odebug "Auditing Bitbucket repo"

      error = SharedAudits.bitbucket(user, repo)
      add_error error, location: url.location if error
    end

    sig { void }
    def audit_forgejo_repository
      return unless new_cask?
      return if (url = cask.url).nil?

      user, repo = get_repo_data(%r{https?://codeberg\.org/([^/]+)/([^/]+)/?.*})
      return if user.nil? || repo.nil?

      odebug "Auditing Forgejo repo"

      error = SharedAudits.forgejo(user, repo)
      add_error error, location: url.location if error
    end

    sig { void }
    def audit_conflicts_with
      return if !cask.tap.official? || cask.conflicts_with.nil?

      Homebrew.with_no_api_env do
        nonexisting_conflicting_casks = cask.conflicts_with.fetch(:cask, Set.new) - core_cask_tokens
        nonexisting_conflicting_casks.each do |c|
          add_error("cask conflicts with non-existing cask `#{c}`")
        end
      end
    end

    sig { void }
    def audit_denylist
      return unless cask.tap
      return unless cask.tap.official?
      return unless (reason = Denylist.reason(cask.token))

      add_error "#{cask.token} is not allowed: #{reason}"
    end

    sig { void }
    def audit_reverse_migration
      return unless new_cask?
      return unless cask.tap
      return unless cask.tap.official?
      return unless cask.tap.tap_migrations.key?(cask.token)

      add_error "#{cask.token} is listed in tap_migrations.json"
    end

    sig { void }
    def audit_homepage_https_availability
      return unless online?
      return unless (homepage = cask.homepage)

      user_agents = if cask.tap&.audit_exception(:simple_user_agent_for_homepage, cask.token)
        ["curl"]
      else
        [:browser, :default]
      end

      validate_url_for_https_availability(
        homepage, SharedAudits::URL_TYPE_HOMEPAGE,
        user_agents:,
        check_content: true,
        strict:        strict?
      )
    end

    sig { void }
    def audit_url_https_availability
      return unless online?
      return unless (url = cask.url)
      return if url.using

      validate_url_for_https_availability(
        url, "binary URL",
        location:    url.location,
        user_agents: [url.user_agent],
        referer:     url.referer
      )
    end

    sig { void }
    def audit_livecheck_https_availability
      return unless online?
      return unless cask.livecheck_defined?
      return unless (url = cask.livecheck.url)
      return if url.is_a?(Symbol)

      options = cask.livecheck.options
      return if options.post_form || options.post_json

      # Validating HTTPS availability is unnecessary if the check uses HTTPS
      # and does not fail.
      if url.start_with?("https:") && audit_livecheck_version != false
        odebug "Skipping livecheck_https_availability audit (working HTTPS livecheck)"
        return
      end

      odebug "Auditing livecheck HTTPS availability"
      validate_url_for_https_availability(
        url, "livecheck URL",
        check_content: true,
        user_agents:   [:default, :browser]
      )
    end

    sig { void }
    def audit_cask_path
      return unless cask.tap.core_cask_tap?

      expected_path = cask.tap.new_cask_path(cask.token)

      return if cask.sourcefile_path.to_s.end_with?(expected_path)

      add_error "Cask should be located in '#{expected_path}'"
    end

    sig { void }
    def audit_deprecate_disable
      error = SharedAudits.check_deprecate_disable_reason(cask)
      add_error error if error
    end

    sig { void }
    def audit_no_autobump
      return if cask.autobump?
      return unless new_cask?

      error = SharedAudits.no_autobump_new_package_message(cask.no_autobump_message)
      add_error error if error
    end

    sig {
      params(
        url_to_check: T.any(String, URL),
        url_type:     String,
        location:     T.nilable(Homebrew::SourceLocation),
        options:      T.untyped,
      ).void
    }
    def validate_url_for_https_availability(url_to_check, url_type, location: nil, **options)
      problem = curl_check_http_content(url_to_check.to_s, url_type, **options)
      exception = cask.tap&.audit_exception(:secure_connection_audit_skiplist, cask.token, url_to_check.to_s)

      if problem
        add_error problem, location: location unless exception
      elsif exception
        add_error "#{url_to_check} is in the secure connection audit skiplist but does not need to be skipped",
                  location:
      end
    end

    sig { params(regex: T.any(String, Regexp)).returns(T.nilable(T::Array[String])) }
    def get_repo_data(regex)
      return unless online?

      _, user, repo = *regex.match(cask.url.to_s)
      _, user, repo = *regex.match(cask.homepage) unless user
      return if !user || !repo

      repo.gsub!(/.git$/, "")

      [user, repo]
    end

    sig {
      params(regex: T.any(String, Regexp), valid_formats_array: T::Array[T.any(String, Regexp)]).returns(T::Boolean)
    }
    def bad_url_format?(regex, valid_formats_array)
      return false unless cask.url.to_s.match?(regex)

      valid_formats_array.none? { |format| cask.url.to_s.match?(format) }
    end

    sig { returns(T::Boolean) }
    def bad_sourceforge_url?
      bad_url_format?(%r{((downloads|\.dl)\.|//)sourceforge},
                      [
                        %r{\Ahttps://sourceforge\.net/projects/[^/]+/files/latest/download\Z},
                        %r{\Ahttps://downloads\.sourceforge\.net/(?!(project|sourceforge)/)},
                      ])
    end

    sig { returns(T::Boolean) }
    def bad_osdn_url?
      T.must(domain).match?(%r{^(?:\w+\.)*osdn\.jp(?=/|$)})
    end

    sig { returns(T.nilable(String)) }
    def homepage
      URI(cask.homepage.to_s).host
    end

    sig { returns(T.nilable(String)) }
    def domain
      URI(cask.url.to_s).host
    end

    sig { returns(T::Boolean) }
    def url_match_homepage?
      host = cask.url.to_s
      host_uri = URI(host)
      host = if host.match?(/:\d/) && host_uri.port != 80
        "#{host_uri.host}:#{host_uri.port}"
      else
        host_uri.host
      end

      home = homepage
      return false if home.blank?

      home.downcase!
      if (split_host = T.must(host).split(".")).length >= 3
        host = T.must(split_host[-2..]).join(".")
      end
      if (split_home = home.split(".")).length >= 3
        home = T.must(split_home[-2..]).join(".")
      end
      host == home
    end

    sig { params(url: String).returns(String) }
    def strip_url_scheme(url)
      url.sub(%r{^[^:/]+://(www\.)?}, "")
    end

    sig { returns(T.nilable(String)) }
    def url_from_verified
      return unless (verified_url = T.must(cask.url).verified)

      strip_url_scheme(verified_url)
    end

    sig { returns(T::Boolean) }
    def verified_matches_url?
      url_domain, url_path = strip_url_scheme(cask.url.to_s).split("/", 2)
      verified_domain, verified_path = url_from_verified&.split("/", 2)

      domains_match = (url_domain == verified_domain) ||
                      (verified_domain && url_domain&.end_with?(".#{verified_domain}"))
      paths_match = !verified_path || url_path&.start_with?(verified_path)
      (domains_match && paths_match) || false
    end

    sig { returns(T::Boolean) }
    def verified_present?
      cask.url&.verified.present?
    end

    sig { returns(T::Boolean) }
    def file_url?
      URI(cask.url.to_s).scheme == "file"
    end

    sig { returns(Tap) }
    def core_tap
      @core_tap ||= T.let(CoreTap.instance, T.nilable(Tap))
    end

    sig { returns(T::Array[String]) }
    def core_formula_names
      core_tap.formula_names
    end

    sig { returns(Tap) }
    def core_cask_tap
      @core_cask_tap ||= T.let(CoreCaskTap.instance, T.nilable(Tap))
    end

    sig { returns(T::Array[String]) }
    def core_cask_tokens
      core_cask_tap.cask_tokens
    end

    sig { returns(String) }
    def core_formula_url
      formula_path = Formulary.core_path(cask.token)
                              .to_s
                              .delete_prefix(core_tap.path.to_s)
      "#{core_tap.default_remote}/blob/HEAD#{formula_path}"
    end
  end
end
