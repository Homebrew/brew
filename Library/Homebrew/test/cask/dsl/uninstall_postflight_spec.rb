# typed: true
# frozen_string_literal: true

require "test/cask/dsl/shared_examples/base"

RSpec.describe Cask::DSL::UninstallPostflight, :cask do
  subject(:dsl) { described_class.new(cask, class_double(SystemCommand)) }

  let(:cask) { Cask::CaskLoader.load(cask_path("basic-cask")) }

  it_behaves_like Cask::DSL::Base
end
