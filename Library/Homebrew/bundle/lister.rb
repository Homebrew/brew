# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module Lister
      sig {
        params(entries: T::Array[Homebrew::Bundle::Dsl::Entry], formulae: T::Boolean, casks: T::Boolean,
               taps: T::Boolean, mas: T::Boolean, vscode: T::Boolean, go: T::Boolean, flatpak: T::Boolean,
               flatpak_remotes: T::Boolean).void
      }
      def self.list(entries, formulae:, casks:, taps:, mas:, vscode:, go:, flatpak:, flatpak_remotes:)
        entries.each do |entry|
          puts entry.name if show?(entry.type, formulae:, casks:, taps:, mas:, vscode:, go:, flatpak:,
flatpak_remotes:)
        end
      end

      sig {
        params(type: Symbol, formulae: T::Boolean, casks: T::Boolean, taps: T::Boolean, mas: T::Boolean,
               vscode: T::Boolean, go: T::Boolean, flatpak: T::Boolean, flatpak_remotes: T::Boolean).returns(T::Boolean)
      }
      private_class_method def self.show?(type, formulae:, casks:, taps:, mas:, vscode:, go:, flatpak:,
                                          flatpak_remotes:)
        return true if formulae && type == :brew
        return true if casks && type == :cask
        return true if taps && type == :tap
        return true if mas && type == :mas
        return true if vscode && type == :vscode
        return true if go && type == :go
        return true if flatpak && type == :flatpak
        return true if flatpak_remotes && type == :flatpak_remote

        false
      end
    end
  end
end
