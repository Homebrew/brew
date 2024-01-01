# frozen_string_literal: true

require "test/cask/dsl/shared_examples/base"
require "test/cask/dsl/shared_examples/staged"

describe Cask::DSL::Postflight, :cask do
  let(:cask) { Cask::CaskLoader.load(cask_path("basic-cask")) }
  let(:fake_system_command) { class_double(SystemCommand) }
  let(:dsl) { described_class.new(cask, fake_system_command) }

  it_behaves_like Cask::DSL::Base

  it_behaves_like Cask::Staged do
    let(:staged) { dsl }
  end
end
