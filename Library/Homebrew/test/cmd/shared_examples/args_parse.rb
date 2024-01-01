# frozen_string_literal: true

shared_examples "parseable arguments" do
  subject(:method_name) { "#{command_name.tr("-", "_")}_args" }

  let(:command_name) do |example|
    example.metadata[:example_group][:parent_example_group][:description].delete_prefix("brew ")
  end

  it "can parse arguments" do
    require "dev-cmd/#{command_name}" unless require? "cmd/#{command_name}"

    parser = Homebrew.public_send(method_name)

    expect(parser).to respond_to(:parse)
  end
end
