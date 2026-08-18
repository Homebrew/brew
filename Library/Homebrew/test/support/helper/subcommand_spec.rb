# typed: strict
# frozen_string_literal: true

RSpec.describe Test::Helper::Subcommand::Args do
  specify "unknown predicates raise" do
    unknown_predicate = :formuale?

    expect do
      described_class.new(named: []).public_send(unknown_predicate)
    end.to raise_error(NoMethodError)
  end
end
