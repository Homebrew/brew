# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "cask/cask_loader"
require "cask/ci/check"
require "cask/ci/zap_check"
require "cask/installer"
require "json"
require "utils/github/actions"

module Homebrew
  module DevCmd
    # Implements the private helpers used by Homebrew Cask's CI workflow.
    class CaskCi < AbstractCommand
      cmd_args do
        usage_banner <<~EOS
          `cask-ci` <operation> [<cask>]

          Runs Homebrew Cask's internal CI helpers. Supported operations are
          `info`, `snapshot`, `zap-check`, and `check`.
        EOS

        description <<~EOS
          Run Homebrew Cask's internal CI helpers.
          For internal use in Homebrew taps.
        EOS

        named_args min: 1, max: 2

        hide_from_man_page!
      end

      sig { override.void }
      def run
        operation = args.named.fetch(0)
        cask_path = args.named.second

        case operation
        when "info"
          write_cask_info(require_cask_path!(operation, cask_path))
        when "snapshot"
          raise UsageError, "The `snapshot` operation does not accept a cask." if cask_path

          write_snapshot
        when "zap-check"
          Cask::CI::ZapCheck.run(require_cask_path!(operation, cask_path))
        when "check"
          check_snapshot(require_cask_path!(operation, cask_path))
        else
          raise UsageError, "Unknown cask CI operation: #{operation}"
        end
      end

      private

      sig { params(operation: String, cask_path: T.nilable(String)).returns(String) }
      def require_cask_path!(operation, cask_path)
        return cask_path if cask_path

        raise UsageError, "The `#{operation}` operation requires a cask."
      end

      sig { params(cask_path: String).void }
      def write_cask_info(cask_path)
        cask = Cask::CaskLoader.load(cask_path)

        manual_installer = cask.artifacts.any? do |artifact|
          artifact.is_a?(Cask::Artifact::Installer) && artifact.manual_install
        end

        macos_requirement_satisfied = cask.depends_on.macos&.satisfied? != false
        cask_conflicts = cask.conflicts_with&.dig(:cask).to_a.select do |conflict|
          Cask::CaskLoader.load(conflict).installed?
        end
        formula_conflicts = cask.conflicts_with&.dig(:formula).to_a.select do |conflict|
          Formula[conflict].any_version_installed?
        end

        dependencies = Cask::Installer.new(cask).missing_cask_and_formula_dependencies
        cask_dependencies = dependencies.grep(Cask::Cask).map(&:full_name)
        formula_dependencies = dependencies.grep(Formula).map(&:full_name)

        File.open(ENV.fetch("GITHUB_OUTPUT"), "a") do |file|
          file.puts "manual_installer=#{JSON.generate(manual_installer)}"
          file.puts "macos_requirement_satisfied=#{JSON.generate(macos_requirement_satisfied)}"
          file.puts "formula_dependencies=#{JSON.generate(formula_dependencies)}"
        end

        File.open(ENV.fetch("GITHUB_ENV"), "a") do |file|
          file.puts "CASK_CONFLICTS=#{cask_conflicts.join(" ")}" if cask_conflicts.present?
          file.puts "CASK_DEPENDENCIES=#{cask_dependencies.join(" ")}" if cask_dependencies.present?
          file.puts "FORMULA_CONFLICTS=#{formula_conflicts.join(" ")}" if formula_conflicts.present?
        end
      end

      sig { void }
      def write_snapshot
        File.open(ENV.fetch("GITHUB_ENV"), "a") do |file|
          # The HOMEBREW_ prefix allows the snapshot to survive brew's environment filtering.
          file.puts "HOMEBREW_SNAPSHOT_BEFORE=#{JSON.generate(system_snapshot)}"
        end
      end

      sig { params(cask_path: String).void }
      def check_snapshot(cask_path)
        before = JSON.parse(ENV.fetch("HOMEBREW_SNAPSHOT_BEFORE", "{}"), symbolize_names: true)
        after = system_snapshot
        errors = Cask::CI::Check.errors(before, after, cask: Cask::CaskLoader.load(cask_path))

        errors.each do |error|
          puts GitHub::Actions::Annotation.new(:error, error, file: cask_path)
        end

        Homebrew.failed = true if errors.any?
      end

      sig { returns(Cask::CI::Check::Snapshot) }
      def system_snapshot
        Cask::CI::Check.all
      end
    end
  end
end
