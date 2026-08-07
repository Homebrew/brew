# typed: strict
# frozen_string_literal: true

require "extend/os/linux/sandbox/landlock"

module OS
  module Linux
    module Sandbox
      extend T::Helpers

      requires_ancestor { ::Sandbox }

      # `TIOCSCTTY` from `<asm-generic/ioctls.h>`; Ruby does not expose it.
      TIOCSCTTY = 0x540E
      private_constant :TIOCSCTTY

      sig { void }
      def allow_write_temp_and_cache
        allow_write_path "/tmp"
        allow_write_path "/var/tmp"
        allow_write_path HOMEBREW_TEMP
        allow_write_path HOMEBREW_CACHE
      end

      sig { void }
      def allow_cvs
        cvspass = ::Pathname.new("#{Dir.home(ENV.fetch("USER"))}/.cvspass")
        allow_write path: cvspass, type: :literal if cvspass.exist?
      end

      sig { void }
      def allow_fossil
        [".fossil", ".fossil-journal"].each do |file|
          fossil_file = ::Pathname.new("#{Dir.home(ENV.fetch("USER"))}/#{file}")
          allow_write path: fossil_file, type: :literal if fossil_file.exist?
        end
      end

      module ClassMethods
        extend T::Helpers

        requires_ancestor { T.class_of(::Sandbox) }

        sig { returns(T::Boolean) }
        def available?
          ::Sandbox::Landlock.available?
        end

        sig { returns(T::Boolean) }
        def full_write_isolation?
          ::Sandbox::Landlock.full_write_isolation?
        end

        sig { returns(Symbol) }
        def state
          ::Sandbox::Landlock.state
        end

        sig { void }
        def reset_state!
          ::Sandbox::Landlock.reset_state!
        end

        sig { returns(T.nilable(String)) }
        def failure_reason
          return super if self != ::Sandbox

          ::Sandbox::Landlock.failure_reason
        end

        # `ioctl` request used to attach the sandboxed child to a controlling TTY.
        sig { returns(Integer) }
        def terminal_ioctl_request
          TIOCSCTTY
        end
      end

      sig { params(args: T.any(String, ::Pathname)).void }
      def run(*args)
        landlock.run { super }
      end

      private

      sig { params(args: T::Array[T.any(String, ::Pathname)], tmpdir: String).returns(T::Array[T.any(String, ::Pathname)]) }
      def sandbox_command(args, tmpdir)
        landlock.command(args, tmpdir)
      end

      sig { void }
      def apply_sandbox
        landlock.apply!
      end

      sig { returns(::Sandbox::Landlock) }
      def landlock
        @landlock ||= T.let(::Sandbox::Landlock.new(profile), T.nilable(::Sandbox::Landlock))
      end
    end
  end
end

Sandbox.prepend(OS::Linux::Sandbox)
Sandbox.singleton_class.prepend(OS::Linux::Sandbox::ClassMethods)
