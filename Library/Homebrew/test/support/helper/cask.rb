# typed: strict
# frozen_string_literal: true

require "cask/cask_loader"

module Test
  module Helper
    module Cask
      extend T::Helpers

      requires_ancestor { RSpec::Mocks::ExampleMethods }

      sig { params(cask: ::Cask::Cask, ref: T.nilable(String), call_original: T::Boolean).void }
      def stub_cask_loader(cask, ref = cask.token, call_original: false)
        allow(::Cask::CaskLoader).to receive(:loader_for).and_call_original if call_original

        loader = instance_double(::Cask::CaskLoader::FromAPILoader, load: cask)
        allow(::Cask::CaskLoader).to receive(:loader_for).with(ref, any_args).and_return(loader)
      end

      sig { params(path: Pathname, short_version: T.nilable(String), bundle_version: T.nilable(String)).void }
      def stub_cask_bundle_version(path, short_version: nil, bundle_version: nil)
        info_plist = path/"Contents/Info.plist"
        info_plist.dirname.mkpath
        FileUtils.touch info_plist
        allow(Homebrew::BundleVersion).to receive(:from_info_plist)
          .with(info_plist)
          .and_return(Homebrew::BundleVersion.new(short_version, bundle_version))
      end
    end
  end
end
