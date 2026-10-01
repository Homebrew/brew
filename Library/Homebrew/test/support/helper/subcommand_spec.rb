# typed: strict
# frozen_string_literal: true

RSpec.describe Test::Helper::Subcommand::Args do
  specify "unknown predicates raise" do
    expect do
      # Intentionally calling an undefined method to check the runtime `NoMethodError`.
      T.unsafe(described_class.new(named: [])).formuale? # rubocop:disable Sorbet/ForbidTUnsafe
    end.to raise_error(NoMethodError)
  end
end
