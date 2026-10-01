# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module TestBot
      module ClassMethods
        extend T::Helpers

        requires_ancestor { T.class_of(::Homebrew::TestBot) }

        sig { returns(String) }
        def runner_os_title
          OS.kernel_name
        end

        sig { returns(String) }
        def runner_os_title_with_arch
          "#{runner_os_title} #{::Hardware::CPU.arch}"
        end
      end

      module TestFormulae
        extend T::Helpers

        requires_ancestor { ::Homebrew::TestBot::TestFormulae }

        sig { returns(String) }
        def previous_run_artifact_specifier
          "{linux,ubuntu}"
        end
      end

      module CleanupBefore
        extend T::Helpers

        requires_ancestor { ::Homebrew::TestBot::CleanupBefore }

        sig { void }
        def cleanup_github_actions_hosted_runner
          # brew doctor complains
          delete_or_move %w[
            /usr/local/include/node/
            /opt/pipx_bin/ansible-config
          ].map { |path| ::Pathname.new(path) }, sudo: true
        end
      end
    end
  end
end

Homebrew::TestBot.singleton_class.prepend(OS::Linux::TestBot::ClassMethods)
Homebrew::TestBot::TestFormulae.prepend(OS::Linux::TestBot::TestFormulae)
Homebrew::TestBot::CleanupBefore.prepend(OS::Linux::TestBot::CleanupBefore)
