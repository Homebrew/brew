# typed: strict
# frozen_string_literal: true

require "cask/artifact/abstract_artifact"
require "install_steps"

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

      sig { params(command: T.class_of(SystemCommand)).returns(Homebrew::InstallSteps::Runner) }
      def runner(command)
        Homebrew::InstallSteps::Runner.new(context: cask, command:)
      end
    end

    # Artifact corresponding to the `preflight_steps` stanza.
    class PreflightSteps < AbstractInstallSteps
      sig { params(command: T.class_of(SystemCommand), _options: T.anything).void }
      def install_phase(command: SystemCommand, **_options)
        runner(command).run(steps)
      end

      sig { params(command: T.class_of(SystemCommand), _options: T.anything).void }
      def uninstall_phase(command: SystemCommand, **_options)
        runner(command).run(steps, phase: :uninstall)
      end
    end

    # Artifact corresponding to the `postflight_steps` stanza.
    class PostflightSteps < AbstractInstallSteps
      sig { params(command: T.class_of(SystemCommand), _options: T.anything).void }
      def install_phase(command: SystemCommand, **_options)
        runner(command).run(steps)
      end

      sig { params(command: T.class_of(SystemCommand), _options: T.anything).void }
      def uninstall_phase(command: SystemCommand, **_options)
        runner(command).run(steps, phase: :uninstall)
      end
    end

    # Artifact corresponding to the `uninstall_preflight_steps` stanza.
    class UninstallPreflightSteps < AbstractInstallSteps
      sig { params(command: T.class_of(SystemCommand), _options: T.anything).void }
      def uninstall_phase(command: SystemCommand, **_options)
        runner(command).run(steps)
      end
    end

    # Artifact corresponding to the `uninstall_postflight_steps` stanza.
    class UninstallPostflightSteps < AbstractInstallSteps
      sig { params(command: T.class_of(SystemCommand), _options: T.anything).void }
      def uninstall_phase(command: SystemCommand, **_options)
        runner(command).run(steps)
      end
    end
  end
end
