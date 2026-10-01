# typed: strict
# frozen_string_literal: true

RSpec.describe "brew --taps", type: :system do
  it_behaves_like "a documented command", "--taps", shell: true
end
