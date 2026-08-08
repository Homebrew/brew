# typed: strict
# frozen_string_literal: true

require "cask/artifact/abstract_artifact"
require "install_steps"
require "keg"

module Cask
  module Artifact
    # Abstract superclass for install steps artifacts.
    class AbstractInstallSteps < AbstractArtifact
      abstract!

      sig { params(cask: Cask, steps: Homebrew::InstallSteps::Steps).void }
      def initialize(cask, steps)
        super
        @steps = T.let(Homebrew::InstallSteps::DSL.normalise_steps(steps), Homebrew::InstallSteps::Steps)
      end

      sig { returns(Homebrew::InstallSteps::Steps) }
      attr_reader :steps

      sig { override.returns(T::Array[T.anything]) }
      def to_args = [{ steps: }]

      sig { override.returns(String) }
      def summarize
        ::Utils.pluralize("install step", steps.length, include_count: true)
      end

      private

      sig { params(command: T.class_of(SystemCommand), phase: Symbol).void }
      def run_steps(command, phase: :install)
        runner = Homebrew::InstallSteps::Runner.new(context: cask, command:)
        sandbox = cask_sandbox
        unless sandbox
          runner.run(steps, phase:)
          return
        end

        sandbox.allow_write_path cask.caskroom_path
        sandbox.allow_write_path cask.config.appdir
        Keg.keg_link_directories.each { |directory| sandbox.allow_write_path HOMEBREW_PREFIX/directory }
        original_home = Pathname(Dir.home).expand_path
        runner.sandbox_write_paths(steps, phase:).each do |path|
          sandbox.allow_write_path path
          sandbox.allow_read(path:, type: :subpath) if path.expand_path.ascend.include?(original_home)
        end
        run_cask_sandbox(
          sandbox,
          {
            "action"  => "install_steps",
            "context" => {
              "name"          => cask.name,
              "token"         => cask.token,
              "version"       => cask.version.to_s,
              "staged_path"   => cask.staged_path.to_s,
              "caskroom_path" => cask.caskroom_path.to_s,
              "home"          => Dir.home,
              "config"        => cask.config.to_json,
            },
            "phase"   => phase.to_s,
            "steps"   => steps,
          },
        )
      end
    end

    # Artifact corresponding to the `preflight_steps` stanza.
    class PreflightSteps < AbstractInstallSteps
      sig { params(command: T.class_of(SystemCommand), _options: T.anything).void }
      def install_phase(command: SystemCommand, **_options)
        run_steps(command)
      end

      sig { params(command: T.class_of(SystemCommand), _options: T.anything).void }
      def uninstall_phase(command: SystemCommand, **_options)
        run_steps(command, phase: :uninstall)
      end
    end

    # Artifact corresponding to the `postflight_steps` stanza.
    class PostflightSteps < AbstractInstallSteps
      sig { params(command: T.class_of(SystemCommand), _options: T.anything).void }
      def install_phase(command: SystemCommand, **_options)
        run_steps(command)
      end

      sig { params(command: T.class_of(SystemCommand), _options: T.anything).void }
      def uninstall_phase(command: SystemCommand, **_options)
        run_steps(command, phase: :uninstall)
      end
    end

    # Artifact corresponding to the `uninstall_preflight_steps` stanza.
    class UninstallPreflightSteps < AbstractInstallSteps
      sig { params(command: T.class_of(SystemCommand), _options: T.anything).void }
      def uninstall_phase(command: SystemCommand, **_options)
        run_steps(command)
      end
    end

    # Artifact corresponding to the `uninstall_postflight_steps` stanza.
    class UninstallPostflightSteps < AbstractInstallSteps
      sig { params(command: T.class_of(SystemCommand), _options: T.anything).void }
      def uninstall_phase(command: SystemCommand, **_options)
        run_steps(command)
      end
    end
  end
end
