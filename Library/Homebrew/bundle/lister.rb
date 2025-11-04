# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module Lister
      sig {
        params(entries: T::Array[Homebrew::Bundle::Dsl::Entry], formulae: T::Boolean, casks: T::Boolean,
               taps: T::Boolean, mas: T::Boolean, vscode: T::Boolean, go: T::Boolean).void
      }
      def self.list(entries, formulae:, casks:, taps:, mas:, vscode:, go:)
        entries.each do |entry|
          puts entry.name if show?(entry.type, formulae:, casks:, taps:, mas:, vscode:, go:)
        end
      end

      sig {
        params(type: Symbol, formulae: T::Boolean, casks: T::Boolean, taps: T::Boolean, mas: T::Boolean,
               vscode: T::Boolean, go: T::Boolean).returns(T::Boolean)
      }
      private_class_method def self.show?(type, formulae:, casks:, taps:, mas:, vscode:, go:)
        return true if formulae && type == :brew
        return true if casks && type == :cask
        return true if taps && type == :tap
        return true if mas && type == :mas
        return true if vscode && type == :vscode
        return true if go && type == :go

        false
      end
    end
  end
end
