# typed: strict
# frozen_string_literal: true

require "cask/cask_loader"
require "cask/ci/check"
require "cask/ci/zap_check"
require "cask/installer"

module Homebrew
  module TestBot
    class Casks < Test
      sig { params(names: T::Array[String], added_casks: T::Array[String], args: Homebrew::Cmd::TestBotCmd::Args).void }
      def run!(names, added_casks:, args:)
        return if names.empty?

        test_header(:Casks)
        default_tap = tap || CoreCaskTap.instance
        added_casks = added_casks.map { |name| name.include?("/") ? name : "#{default_tap}/#{name}" }
        Utils::Shell.with_env(HOMEBREW_TEST_BOT_CASKS: ("1" if CoreCaskTap.instance.installed?)) do
          CoreCaskTap.instance.clear_cache
          names.each do |name|
            name = "#{default_tap}/#{name}" if name.exclude?("/") && !default_tap.core_cask_tap?
            begin
              cask = Cask::CaskLoader.load(name)
            rescue => e
              # Even a dry run needs the cask definition to plan its steps.
              test("Load cask", name, dry_run: false) { raise e }
              next
            end

            if cask.disabled? || !cask.meets_platform_requirements?(Utils::Bottles.tag)
              info_header "Skipping #{name} (disabled or unsupported on #{Utils::Bottles.tag})"
              next
            end

            fetched = fetch(:cask, name, args:)
            new_cask = added_casks.include?("#{cask.tap}/#{cask.token}") || added_casks.include?(name)
            test(*audit_command(:cask, name, args:, new_package: new_cask), report_analytics: true)
            next if args.skip_install? || !fetched.passed?

            path = cask.sourcefile_path || raise("No tap file for #{cask.full_name}")
            installer = Cask::Installer.new(cask, verbose: args.verbose?)
            if cleanup?(args)
              conflicts = T.let(nil, T.nilable(T::Array[String]))
              test("Resolve conflicts", cask.full_name, dry_run: false) { conflicts = installer.installed_conflicts }
              next unless conflicts

              test "brew", "uninstall", "--cask", *conflicts if conflicts.present?
              test "brew", "uninstall", "--cask", "--force", "--zap", cask.full_name
            end

            dependencies = T.let([], T::Array[Cask::Cask])
            resolved = test("Resolve dependencies", cask.full_name) do
              dependencies = installer.missing_cask_and_formula_dependencies.grep(Cask::Cask)
            end
            next unless resolved.passed?

            snapshot = (@dry_run ? {} : Cask::CI::Check.all) if cleanup?(args) && Utils::Bottles.tag.macos?
            already_installed = cask.installed?
            install_args = ["brew", "install", "--cask", cask.full_name]
            install_args << "--verbose" if args.verbose?
            begin
              if already_installed && !@dry_run
                test(*install_args) { raise Cask::CaskError, "#{cask} is already installed." }
                next
              end
              installed = test(*install_args,
                               env:              { "HOMEBREW_NO_ASK" => "1", "HOMEBREW_NO_INSTALL_CLEANUP" => "1" },
                               report_analytics: true).passed?
              if installed && snapshot
                test("Check zap stanza", cask.full_name, ignore_failures: true) { Cask::CI::ZapCheck.run(path.to_s) }
              end
            ensure
              if !already_installed && (installed || cask.installed?) &&
                 cask.artifacts.grep(Cask::Artifact::Installer).none?(&:manual_install)
                test "brew", "uninstall", "--cask", cask.full_name
              end
              installed_dependencies = dependencies.select(&:installed?).map(&:full_name).reverse
              test "brew", "uninstall", "--cask", *installed_dependencies if installed_dependencies.present?
              if installed && snapshot
                test("Check uninstall", cask.full_name) do
                  errors = Cask::CI::Check.errors(snapshot, Cask::CI::Check.all, cask:)
                  errors.each { |error| puts GitHub::Actions::Annotation.new(:error, error, file: path.to_s) }
                  raise Cask::CaskError, errors.join("\n") if errors.any?
                end
              end
            end
          end
        ensure
          CoreCaskTap.instance.clear_cache
        end
      end
    end
  end
end
