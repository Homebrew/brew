# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module DevCmd
      module Tests
        extend T::Helpers

        requires_ancestor { Homebrew::DevCmd::Tests }

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
