# typed: true
# frozen_string_literal: true

RSpec.describe "Standalone::Sorbet" do
  # `HOMEBREW_SORBET_RUNTIME` is always set for the RSpec process (see `dev-cmd/tests.rb`), so
  # the no-op type constructors this exercises never run in-process here: shell out with the
  # runtime disabled, exactly as every real `brew` invocation does.
  it "keeps a non-nilable prop's `default:` applied on deserialization, without making nilable " \
     "props non-nilable", :integration_test do
    script = <<~RUBY
      class SorbetNoOpRegressionStruct < T::Struct
        const :names, T::Array[String], default: []
        const :maybe, T.nilable(String)
      end

      struct = SorbetNoOpRegressionStruct.from_hash({}, ignore_types: true)
      raise "array prop lost its default: \#{struct.names.inspect}" unless struct.names == []
      raise "nilable prop is no longer nilable: \#{struct.maybe.inspect}" unless struct.maybe.nil?
    RUBY

    expect do
      brew "ruby", "-e", script, "HOMEBREW_SORBET_RUNTIME" => nil, "HOMEBREW_SORBET_RECURSIVE" => nil
    end.to be_a_success
  end
end
