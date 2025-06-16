# frozen_string_literal: true

require "test/cask/dsl/shared_examples/base"

RSpec.describe Cask::DSL::UninstallPostflight, :cask do
  let(:cask) { Cask::CaskLoader.load(cask_path("basic-cask")) }
  let(:dsl) { described_class.new(cask, class_double(SystemCommand)) }

  it_behaves_like Cask::DSL::Base
end
