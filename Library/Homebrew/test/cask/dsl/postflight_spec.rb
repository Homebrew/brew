# typed: true
# frozen_string_literal: true

require "test/cask/dsl/shared_examples/base"
require "test/cask/dsl/shared_examples/staged"

RSpec.describe Cask::DSL::Postflight, :cask do
  subject(:dsl) { described_class.new(cask, fake_system_command) }

  let(:cask) { Cask::CaskLoader.load(cask_path("basic-cask")) }
  let(:fake_system_command) { class_double(SystemCommand) }

  it_behaves_like Cask::DSL::Base

  it_behaves_like Cask::Staged
end
