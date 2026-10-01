# typed: strict
# frozen_string_literal: true

require "cask/dsl/base"

RSpec.shared_examples Cask::DSL::Base do
  it "supports the token method" do
    expect(subject.token).to eq(subject.cask.token)
  end

  it "supports the version method" do
    expect(subject.version).to eq(subject.cask.version)
  end

  it "supports the caskroom_path method" do
    expect(subject.caskroom_path).to eq(subject.cask.caskroom_path)
  end

  it "supports the staged_path method" do
    expect(subject.staged_path).to eq(subject.cask.staged_path)
  end

  it "supports the appdir method" do
    expect(subject.appdir).to eq(subject.cask.appdir)
  end
end
