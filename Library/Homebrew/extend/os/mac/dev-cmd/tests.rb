# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module DevCmd
      module Tests
        extend T::Helpers

        requires_ancestor { Homebrew::DevCmd::Tests }

        sig { void }
        def check_test_environment!
          super
          # Build the verified index once for spec_helper's per-example clones.
          Homebrew::API::Internal.fetch_packages_api! unless args.load_only?
        end

        private

        sig { params(bundle_args: T::Array[String]).returns(T::Array[String]) }
        def os_bundle_args(bundle_args)
          non_linux_bundle_args(bundle_args)
        end

        sig { params(files: T::Array[String]).returns(T::Array[String]) }
        def os_files(files)
          non_linux_files(files)
        end
      end
    end
  end
end

Homebrew::DevCmd::Tests.prepend(OS::Mac::DevCmd::Tests)
