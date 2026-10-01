# typed: strict
# frozen_string_literal: true

RSpec.describe "brew update-reset", type: :system do
  it_behaves_like "a documented command", "update-reset", shell: true
end
