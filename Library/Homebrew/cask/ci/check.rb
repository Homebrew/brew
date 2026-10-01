# typed: strict
# frozen_string_literal: true

require "cask/artifact/uninstall"
require "cask/pkg"
require "system_command"
require "utils/formatter"

module Cask
  module CI
    # Captures and compares system state around Cask installation tests.
    module Check
      extend SystemCommand::Mixin

      Snapshot = T.type_alias { T::Hash[Symbol, T::Array[String]] }

      APPLE_LAUNCHJOBS_REGEX = /\A(?:application\.)?com\.apple\.
        (AppStore|installer|Preview|Safari|shortcuts|systemevents|systempreferences|Terminal)
        (?:\.|$)/x
      private_constant :APPLE_LAUNCHJOBS_REGEX

      GOOGLE_LAUNCHJOBS_REGEX = /com\.google\.(keystone|GoogleUpdater)/
      private_constant :GOOGLE_LAUNCHJOBS_REGEX

      CHECKS = T.let({
        installed_apps:       lambda {
          ["/Applications", File.expand_path("~/Applications")]
          .flat_map { |dir| (0..5).map { |i| "/*" * i }.flat_map { |glob| Dir["#{dir}#{glob}.app"] } }
        },
        installed_kexts:      lambda {
          system_command!("/usr/sbin/kextstat", args: ["-kl"], print_stderr: false)
          .stdout
          .lines
          .map do |line|
            identifier = line.match(/^.{52}([^\s]+)/)&.[](1)
            raise "Unexpected kextstat output: #{line}" unless identifier

            identifier
          end
          .grep_v(/^com\.apple\./)
        },
        installed_pkgs:       lambda {
          Pathname("/var/db/receipts")
          .children
          .grep(/\.plist$/)
          .map { |path| path.basename.to_s.sub(/\.plist$/, "") }
          .grep_v(/^com\.google(?:\.pkg)?\.Keystone/i)
        },
        installed_launchjobs: lambda {
          format_launchjob = lambda { |file|
            name = file.basename(".plist").to_s

            result = system_command "plutil", args: ["-convert", "xml1", "-o", "-", "--", file], sudo: true
            return name unless result.success?

            label = result.plist["Label"]
            (name == label) ? name : "#{name} (#{label})"
          }

          [
            "~/Library/LaunchAgents",
            "~/Library/LaunchDaemons",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
          ].map { |path| Pathname(path).expand_path }
          .select(&:directory?)
          .flat_map(&:children)
          .grep_v(GOOGLE_LAUNCHJOBS_REGEX)
          .select { |child| child.extname == ".plist" }
          .select(&:exist?)
          .map(&format_launchjob)
        },
        loaded_launchjobs:    lambda {
          launchctl = lambda do |sudo|
            system_command!("/bin/launchctl", args: ["list"], print_stderr: false, sudo:)
            .stdout
            .lines.drop(1)
            .grep_v(APPLE_LAUNCHJOBS_REGEX)
            .grep_v(GOOGLE_LAUNCHJOBS_REGEX)
          end

          [false, true]
          .flat_map(&launchctl)
          .map { |line| line.split(/\s+/).fetch(2) }
          .grep_v(/^com\.apple\./)
          .grep_v(GOOGLE_LAUNCHJOBS_REGEX)
        },
      }.freeze, T::Hash[Symbol, T.proc.returns(T::Array[String])])
      private_constant :CHECKS

      # Represents additions and removals between two snapshots.
      class Diff
        sig { returns(T::Array[String]) }
        attr_reader :removed, :added

        sig { params(before: T::Array[String], after: T::Array[String]).void }
        def initialize(before, after)
          @before = T.let(before.sort.uniq, T::Array[String])
          @after = T.let(after.sort.uniq, T::Array[String])
          @removed = T.let(@before - @after, T::Array[String])
          @added = T.let(@after - @before, T::Array[String])
        end

        sig { returns(T::Boolean) }
        def changed?
          removed.any? || added.any?
        end
      end
      private_constant :Diff

      sig { returns(Snapshot) }
      def self.all
        CHECKS.transform_values(&:call)
      end

      sig { params(before: Snapshot, after: Snapshot, cask: ::Cask::Cask).returns(T::Array[String]) }
      def self.errors(before, after, cask:)
        uninstall_artifact = cask.artifacts.find { |artifact| artifact.is_a?(::Cask::Artifact::Uninstall) }
        uninstall_directives = if uninstall_artifact.is_a?(::Cask::Artifact::Uninstall)
          uninstall_artifact.directives
        else
          {}
        end

        diff = T.let({}, T::Hash[Symbol, Diff])
        CHECKS.each_key do |name|
          diff[name] = Diff.new(before.fetch(name), after.fetch(name))
        end

        errors = T.let([], T::Array[String])

        pkg_files = diff.fetch(:installed_pkgs)
                        .added
                        .flat_map { |id| ::Cask::Pkg.new(id).pkgutil_bom_all.map(&:to_s) }
        installed_apps = diff.fetch(:installed_apps).added - pkg_files
        if installed_apps.any?
          message = "Some applications are still installed, add them to " \
                    "#{Formatter.identifier("uninstall delete:")}\n"
          message += installed_apps.join("\n")
          errors << message
        end

        installed_kexts = diff.fetch(:installed_kexts)
                              .added
                              .grep_v(/^com\.(softraid\.driver\.SoftRAID|highpoint-tech\.kext\.*)/)
        if installed_kexts.any?
          message = "Some kernel extensions are still installed, add them to " \
                    "#{Formatter.identifier("uninstall kext:")}\n"
          message += installed_kexts.join("\n")
          errors << message
        end

        installed_packages = diff.fetch(:installed_pkgs)
                                 .added
                                 .grep_v(/^com\.logi\.installer\.pluginservice\.package/i)
        if installed_packages.any?
          message = "Some packages are still installed, add them to #{Formatter.identifier("uninstall pkgutil:")}\n"
          message += installed_packages.join("\n")
          errors << message
        end

        installed_launchjobs = diff.fetch(:installed_launchjobs).added
        if installed_launchjobs.any?
          message = "Some launch jobs are still installed, add them to " \
                    "#{Formatter.identifier("uninstall launchctl:")}\n"
          message += installed_launchjobs.join("\n")
          errors << message
        end

        running_apps = diff.fetch(:loaded_launchjobs)
                           .added
                           .grep(/\.\d+\z/)
                           .grep_v(APPLE_LAUNCHJOBS_REGEX)
                           .grep_v(GOOGLE_LAUNCHJOBS_REGEX)
                           .map { |id| id.sub(/\A(?:application\.)?(.*?)(?:\.\d+){0,2}\z/, '\\1') }

        loaded_launchjobs = diff.fetch(:loaded_launchjobs)
                                .added
                                .grep_v(/\.\d+\z/)

        missing_running_apps = reject_matching(running_apps, uninstall_directives[:quit])

        # Some applications may launch a browser session after install.
        # Skip Firefox, unless the cask is a Firefox cask.
        missing_running_apps.delete("org.mozilla.firefox") unless cask.token.include?("firefox")

        if missing_running_apps.any?
          message = "Some applications are still running, add them to #{Formatter.identifier("uninstall quit:")}\n"
          message += missing_running_apps.join("\n")
          errors << message
        end

        missing_loaded_launchjobs = reject_matching(
          loaded_launchjobs,
          uninstall_directives[:launchctl],
          anchored:    false,
          ignore_case: false,
        )
        if missing_loaded_launchjobs.any?
          message = "Some launch jobs were not unloaded, add them to " \
                    "#{Formatter.identifier("uninstall launchctl:")}\n"
          message += missing_loaded_launchjobs.join("\n")
          errors << message
        end

        errors
      end

      # Match `*` wildcards as `Cask::Artifact::AbstractUninstall` resolves them:
      # `quit:` anchors and ignores case, `launchctl:` does neither.
      sig {
        params(
          ids:         T::Array[String],
          directives:  Object,
          anchored:    T::Boolean,
          ignore_case: T::Boolean,
        ).returns(T::Array[String])
      }
      def self.reject_matching(ids, directives, anchored: true, ignore_case: true)
        patterns = Array(directives).map do |directive|
          directive = directive.to_s
          source = Regexp.escape(directive).gsub("\\*", ".*")
          source = "\\A#{source}\\z" if anchored || directive.exclude?("*")
          Regexp.new(source, ignore_case ? Regexp::IGNORECASE : nil)
        end
        ids.reject { |id| patterns.any? { |pattern| pattern.match?(id) } }
      end
    end
  end
end
