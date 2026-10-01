# typed: strict
# frozen_string_literal: true

require "utils/github/actions"

module OS
  module Linux
    module DevCmd
      module Tests
        extend T::Helpers

        requires_ancestor { Homebrew::DevCmd::Tests }

        sig { void }
        def check_test_environment!
          super
          return unless Homebrew::EnvConfig.sandbox_linux?

          require "sandbox"
          return if ::Sandbox.available?

          # On CI the sandbox must work, so fail loudly
          # to ensure `brew tests` really runs sandboxed.
          # On a developer's machine the sandbox may be unavailable
          # (e.g. a Ruby without Fiddle, which the Landlock sandbox needs),
          # so warn and run the tests unsandboxed rather than aborting.
          if GitHub::Actions.env_set?
            ::Sandbox.ensure_sandbox_available!
          else
            opoo ::Sandbox.failure_reason || "The sandbox is not available."
          end
        end

        private

        sig { params(bundle_args: T::Array[String]).returns(T::Array[String]) }
        def os_bundle_args(bundle_args)
          non_macos_bundle_args(bundle_args)
        end

        sig { params(files: T::Array[String]).returns(T::Array[String]) }
        def os_files(files)
          non_macos_files(files)
        end
      end
    end
  end
end

Homebrew::DevCmd::Tests.prepend(OS::Linux::DevCmd::Tests)
