# typed: strict
# frozen_string_literal: true

RSpec.describe "brew rubocop", type: :system do
  it_behaves_like "a documented command", "rubocop", shell: true
end
