# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Bundle
      module Checker
        module FlatpakRemoteChecker
          sig {
            params(_entries: T::Array[Homebrew::Bundle::Dsl::Entry], exit_on_first_error: T::Boolean,
                   no_upgrade: T::Boolean, verbose: T::Boolean).returns(T::Array[String])
          }
          def find_actionable(_entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
            []
          end
        end
      end
    end
  end
end

Homebrew::Bundle::Checker::FlatpakRemoteChecker.prepend(OS::Mac::Bundle::Checker::FlatpakRemoteChecker)
