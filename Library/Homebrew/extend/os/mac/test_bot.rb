# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module TestBot
      module ClassMethods
        extend T::Helpers

        requires_ancestor { T.class_of(::Homebrew::TestBot) }

        sig { returns(String) }
        def runner_os_title
          title = "macOS #{MacOS.version.pretty_name} (#{MacOS.version})"
          title << " on Apple Silicon" if ::Hardware::CPU.arm?

          title
        end
      end

      module TestFormulae
        extend T::Helpers

        requires_ancestor { ::Homebrew::TestBot::TestFormulae }

        sig { returns(String) }
        def previous_run_artifact_specifier
          "{macos-#{MacOS.version},#{MacOS.version}-#{::Hardware::CPU.arch}}"
        end
      end

      module Formulae
        extend T::Helpers

        requires_ancestor { ::Homebrew::TestBot::Formulae }

        sig { params(args: ::Homebrew::Cmd::TestBotCmd::Args).void }
        def setup_bottle_sudo_purge!(args:)
          # This is needed where sparse files may be handled (bsdtar >=3.0).
          # We use gnu-tar with sparse files disabled when --only-json-tab is passed.
          ENV["HOMEBREW_BOTTLE_SUDO_PURGE"] = "1" if MacOS.version >= :catalina && !args.only_json_tab?
        end

        sig { returns(T::Boolean) }
        def integration_test_portable_ruby?
          # tests fail on macOS when currently running portable Ruby is replaced using same path
          portable_ruby_version = (HOMEBREW_LIBRARY_PATH/"vendor/portable-ruby-version").read.chomp
          portable_ruby_version != ::Formula["portable-ruby"].pkg_version.to_s
        end
      end

      module FormulaeDependents
        extend T::Helpers

        requires_ancestor { ::Homebrew::TestBot::FormulaeDependents }

        sig { params(_formula: Formula, args: ::Homebrew::Cmd::TestBotCmd::Args).returns(T::Boolean) }
        def skip_recursive_dependents?(_formula, args:)
          super || ::Hardware::CPU.intel?
        end
      end

      module CleanupBefore
        extend T::Helpers

        requires_ancestor { ::Homebrew::TestBot::CleanupBefore }

        sig { void }
        def cleanup_github_actions_hosted_runner
          delete_or_move HOMEBREW_CELLAR.glob("*")
          delete_or_move HOMEBREW_CASKROOM.glob("session-manager-plugin")

          delete_or_move %w[
            Mono.framework
            PluginManager.framework
            Python.framework
            R.framework
            Xamarin.Android.framework
            Xamarin.Mac.framework
            Xamarin.iOS.framework
          ].map { |framework| ::Pathname.new("/Library/Frameworks")/framework }, sudo: true
        end
      end
    end
  end
end

Homebrew::TestBot.singleton_class.prepend(OS::Mac::TestBot::ClassMethods)
Homebrew::TestBot::TestFormulae.prepend(OS::Mac::TestBot::TestFormulae)
Homebrew::TestBot::Formulae.prepend(OS::Mac::TestBot::Formulae)
Homebrew::TestBot::FormulaeDependents.prepend(OS::Mac::TestBot::FormulaeDependents)
Homebrew::TestBot::CleanupBefore.prepend(OS::Mac::TestBot::CleanupBefore)
