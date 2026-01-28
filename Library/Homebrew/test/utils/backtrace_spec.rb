# frozen_string_literal: true

require "utils/backtrace"

RSpec.describe Utils::Backtrace do
  let(:backtrace_no_sorbet_paths) do
    [
      "/Library/Homebrew/downloadable.rb:75:in",
      "/Library/Homebrew/downloadable.rb:50:in",
      "/Library/Homebrew/cmd/fetch.rb:236:in",
      "/Library/Homebrew/cmd/fetch.rb:201:in",
      "/Library/Homebrew/cmd/fetch.rb:178:in",
      "/Library/Homebrew/simulate_system.rb:29:in",
      "/Library/Homebrew/cmd/fetch.rb:166:in",
      "/Library/Homebrew/cmd/fetch.rb:163:in",
      "/Library/Homebrew/cmd/fetch.rb:163:in",
      "/Library/Homebrew/cmd/fetch.rb:94:in",
      "/Library/Homebrew/cmd/fetch.rb:94:in",
      "/Library/Homebrew/brew.rb:94:in",
    ]
  end

  let(:backtrace_with_sorbet_paths) do
    [
      "/Library/Homebrew/downloadable.rb:75:in",
      "/Library/Homebrew/vendor/bundle/ruby/2.6.0/gems/sorbet-runtime-0.5.10461/lib/call_validation.rb:157:in",
      "/Library/Homebrew/vendor/bundle/ruby/2.6.0/gems/sorbet-runtime-0.5.10461/lib/call_validation.rb:157:in",
      "/Library/Homebrew/vendor/bundle/ruby/2.6.0/gems/sorbet-runtime-0.5.10461/lib/_methods.rb:270:in",
      "/Library/Homebrew/downloadable.rb:50:in",
      "/Library/Homebrew/vendor/bundle/ruby/2.6.0/gems/sorbet-runtime-0.5.10461/lib/call_validation.rb:157:in",
      "/Library/Homebrew/vendor/bundle/ruby/2.6.0/gems/sorbet-runtime-0.5.10461/lib/call_validation.rb:157:in",
      "/Library/Homebrew/vendor/bundle/ruby/2.6.0/gems/sorbet-runtime-0.5.10461/lib/_methods.rb:270:in",
      "/Library/Homebrew/cmd/fetch.rb:236:in",
      "/Library/Homebrew/cmd/fetch.rb:201:in",
      "/Library/Homebrew/cmd/fetch.rb:178:in",
      "/Library/Homebrew/simulate_system.rb:29:in",
      "/Library/Homebrew/vendor/bundle/ruby/2.6.0/gems/sorbet-runtime-0.5.10461/lib/call_validation.rb:157:in",
      "/Library/Homebrew/vendor/bundle/ruby/2.6.0/gems/sorbet-runtime-0.5.10461/lib/call_validation.rb:157:in",
      "/Library/Homebrew/vendor/bundle/ruby/2.6.0/gems/sorbet-runtime-0.5.10461/lib/_methods.rb:270:in",
      "/Library/Homebrew/cmd/fetch.rb:166:in",
      "/Library/Homebrew/cmd/fetch.rb:163:in",
      "/Library/Homebrew/cmd/fetch.rb:163:in",
      "/Library/Homebrew/cmd/fetch.rb:94:in",
      "/Library/Homebrew/cmd/fetch.rb:94:in",
      "/Library/Homebrew/brew.rb:94:in",
    ]
  end

  let(:backtrace_with_sorbet_error) do
    backtrace_with_sorbet_paths.drop(1)
  end

  def exception_with(backtrace:)
    exception = StandardError.new
    exception.set_backtrace(backtrace) if backtrace
    exception
  end

  before do
    allow(described_class).to receive(:sorbet_runtime_path)
      .and_return("/Library/Homebrew/vendor/bundle/ruby/2.6.0/gems/sorbet-runtime")
    allow(Context).to receive(:current).and_return(Context::ContextStruct.new(verbose: false))
  end

  it "handles nil backtrace" do
    exception = exception_with backtrace: nil
    expect(described_class.clean(exception)).to be_nil
  end

  it "handles empty array backtrace" do
    exception = exception_with backtrace: []
    expect(described_class.clean(exception)).to eq []
  end

  it "removes sorbet paths when top error is not from sorbet" do
    exception = exception_with backtrace: backtrace_with_sorbet_paths
    expect(described_class.clean(exception)).to eq backtrace_no_sorbet_paths
  end

  it "includes sorbet paths when top error is not from sorbet and verbose is set" do
    allow(Context).to receive(:current).and_return(Context::ContextStruct.new(verbose: true))
    exception = exception_with backtrace: backtrace_with_sorbet_paths
    expect(described_class.clean(exception)).to eq backtrace_with_sorbet_paths
  end

  it "doesn't change backtrace when error is from sorbet" do
    exception = exception_with backtrace: backtrace_with_sorbet_error
    expect(described_class.clean(exception)).to eq backtrace_with_sorbet_error
  end
end
