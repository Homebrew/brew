# typed: strict
# frozen_string_literal: true

require "utils/output"

module OS
  module Mac
    module Install
      module ClassMethods
        include ::Utils::Output::Mixin

        sig { void }
        def check_prefix
          if (::Hardware::CPU.intel? || ::Hardware::CPU.in_rosetta2?) &&
             HOMEBREW_PREFIX.to_s == HOMEBREW_MACOS_ARM_DEFAULT_PREFIX
            if ::Hardware::CPU.in_rosetta2?
              odie <<~EOS
                Cannot install under Rosetta 2 in ARM default prefix (#{HOMEBREW_PREFIX})!
                To rerun under ARM use:
                    arch -arm64 brew install ...
                To install under x86_64, install Homebrew into #{HOMEBREW_DEFAULT_PREFIX}.
              EOS
            else
              odie "Cannot install on Intel processor in ARM default prefix (#{HOMEBREW_PREFIX})!"
            end
          elsif ::Hardware::CPU.arm? && HOMEBREW_PREFIX.to_s == HOMEBREW_DEFAULT_PREFIX
            odie <<~EOS
              Cannot install in Homebrew on ARM processor in Intel default prefix (#{HOMEBREW_PREFIX})!
              Please create a new installation in #{HOMEBREW_MACOS_ARM_DEFAULT_PREFIX} using one of the
              "Alternative Installs" from:
                #{Formatter.url("https://docs.brew.sh/Installation")}
              You can migrate your previously installed formula list with:
                brew bundle dump
            EOS
          end
        end
      end
    end
  end
end

Homebrew::Install.singleton_class.prepend(OS::Mac::Install::ClassMethods)
