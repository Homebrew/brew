# typed: strict
# frozen_string_literal: true

RSpec.describe "brew rubydoc", type: :system do
  it_behaves_like "a documented command", "rubydoc"
end
