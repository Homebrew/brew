# frozen_string_literal: true

require "cask/cask_loader"

module Test
  module Helper
    module Cask
      def stub_cask_loader(cask, ref = cask.token, call_original: false)
        allow(::Cask::CaskLoader).to receive(:for).and_call_original if call_original

        loader = ::Cask::CaskLoader::FromInstanceLoader.new(cask)
        allow(::Cask::CaskLoader).to receive(:for).with(ref, any_args).and_return(loader)
      end
    end
  end
end
