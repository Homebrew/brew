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

      sig { override.returns(T::Boolean) }
      def requires_sudo?
        respond_to?(:install_phase) &&
          Homebrew::InstallSteps::Runner.new(context: cask).sudo_required?(steps, include_optional: false)
      end

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
        sandbox = cask_sandbox(network_access_allowed: steps.any? do |step|
          step["type"] == "run" && step["network_access"] == true
        end)
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
        payload = {
          "action"  => "install_steps",
          "context" => {
            "name"          => cask.name,
            "token"         => cask.token,
            "arch"          => cask.arch,
            "version"       => cask.version.to_s,
            "staged_path"   => cask.staged_path.to_s,
            "caskroom_path" => cask.caskroom_path.to_s,
            "home"          => Dir.home,
            "config"        => cask.config.to_json,
          },
          "phase"   => phase.to_s,
          "steps"   => steps,
        }
        unless runner.sudo_required?(steps)
          run_cask_sandbox(sandbox, payload)
          return
        end

        last_privileged_index = T.let(-1, Integer)
        # macOS caches sudo credentials per terminal or session, so privileged
        # steps must run in this parent process to reuse its ticket instead of
        # prompting once per sandbox child PTY.
        child_message_handler = proc do |message|
          index = run_privileged_step_request(message, runner:, phase:, last_privileged_index:)
          next if index.nil?

          last_privileged_index = index
          Homebrew::InstallSteps::Runner::PRIVILEGED_STEP_SUCCEEDED
        end

        # Keep the parent terminal free for the sudo prompt: forwarded
        # sandbox stdin would otherwise compete for the password input.
        run_cask_sandbox(
          sandbox,
          payload,
          passthrough_stdin:     false,
          child_message_handler:,
        )
      end

      sig {
        params(
          message:               String,
          runner:                Homebrew::InstallSteps::Runner,
          phase:                 Symbol,
          last_privileged_index: Integer,
        ).returns(T.nilable(Integer))
      }
      def run_privileged_step_request(message, runner:, phase:, last_privileged_index:)
        request = begin
          JSON.parse(message)
        rescue JSON::ParserError
          nil
        end
        # Child error reports arrive on the same pipe; leave them for
        # `Utils.safe_fork` to raise.
        return if request.is_a?(Hash) && request.key?("json_class")

        # The sandboxed child is untrusted and may only nominate a predeclared
        # privileged step by index.
        if !request.is_a?(Hash) ||
           request["type"] != Homebrew::InstallSteps::Runner::PRIVILEGED_STEP_REQUEST
          raise ArgumentError, "Invalid privileged cask child message."
        end

        index = request.fetch("index")
        unless index.is_a?(Integer)
          raise ArgumentError,
                "Invalid privileged cask install step index: #{index.inspect}"
        end
        if index <= last_privileged_index
          raise ArgumentError, "Privileged cask install steps must be requested in order."
        end

        step = steps.fetch(index)
        unless runner.sudo_required?([step])
          raise ArgumentError, "Cask install step #{index} is not privileged."
        end

        # Re-evaluate guards in the parent instead of trusting the child, while
        # preserving snapshots across requests from the same step plan.
        runner.run([step], phase:, reset_guard_results: false)
        index
      end
    end

    # Artifact corresponding to the `preflight_steps` stanza.
    class PreflightSteps < AbstractInstallSteps
      sig {
        params(
          adopt:        T::Boolean,
          auto_updates: T.nilable(T::Boolean),
          force:        T::Boolean,
          verbose:      T::Boolean,
          predecessor:  T.nilable(Cask),
          command:      T.class_of(SystemCommand),
        ).void
      }
      def install_phase(adopt: false, auto_updates: false, force: false, verbose: false, predecessor: nil,
                        command: SystemCommand)
        run_steps(command)
      end

      sig {
        params(
          skip:      T::Boolean,
          force:     T::Boolean,
          verbose:   T::Boolean,
          successor: T.nilable(Cask),
          upgrade:   T::Boolean,
          reinstall: T::Boolean,
          command:   T.class_of(SystemCommand),
        ).void
      }
      def uninstall_phase(skip: false, force: false, verbose: false, successor: nil, upgrade: false,
                          reinstall: false, command: SystemCommand)
        run_steps(command, phase: :uninstall)
      end
    end

    # Artifact corresponding to the `postflight_steps` stanza.
    class PostflightSteps < AbstractInstallSteps
      sig {
        params(
          adopt:        T::Boolean,
          auto_updates: T.nilable(T::Boolean),
          force:        T::Boolean,
          verbose:      T::Boolean,
          predecessor:  T.nilable(Cask),
          command:      T.class_of(SystemCommand),
        ).void
      }
      def install_phase(adopt: false, auto_updates: false, force: false, verbose: false, predecessor: nil,
                        command: SystemCommand)
        run_steps(command)
      end

      sig {
        params(
          skip:      T::Boolean,
          force:     T::Boolean,
          verbose:   T::Boolean,
          successor: T.nilable(Cask),
          upgrade:   T::Boolean,
          reinstall: T::Boolean,
          command:   T.class_of(SystemCommand),
        ).void
      }
      def uninstall_phase(skip: false, force: false, verbose: false, successor: nil, upgrade: false,
                          reinstall: false, command: SystemCommand)
        run_steps(command, phase: :uninstall)
      end
    end

    # Artifact corresponding to the `uninstall_preflight_steps` stanza.
    class UninstallPreflightSteps < AbstractInstallSteps
      sig {
        params(
          skip:      T::Boolean,
          force:     T::Boolean,
          verbose:   T::Boolean,
          successor: T.nilable(Cask),
          upgrade:   T::Boolean,
          reinstall: T::Boolean,
          command:   T.class_of(SystemCommand),
        ).void
      }
      def uninstall_phase(skip: false, force: false, verbose: false, successor: nil, upgrade: false,
                          reinstall: false, command: SystemCommand)
        run_steps(command)
      end
    end

    # Artifact corresponding to the `uninstall_postflight_steps` stanza.
    class UninstallPostflightSteps < AbstractInstallSteps
      sig {
        params(
          skip:      T::Boolean,
          force:     T::Boolean,
          verbose:   T::Boolean,
          successor: T.nilable(Cask),
          upgrade:   T::Boolean,
          reinstall: T::Boolean,
          command:   T.class_of(SystemCommand),
        ).void
      }
      def uninstall_phase(skip: false, force: false, verbose: false, successor: nil, upgrade: false,
                          reinstall: false, command: SystemCommand)
        run_steps(command)
      end
    end
  end
end
