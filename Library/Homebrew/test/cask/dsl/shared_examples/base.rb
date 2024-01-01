# frozen_string_literal: true

require "cask/dsl/base"

shared_examples Cask::DSL::Base do
  it "supports the token method" do
    expect(dsl.token).to eq(cask.token)
  end

  it "supports the version method" do
    expect(dsl.version).to eq(cask.version)
  end

  it "supports the caskroom_path method" do
    expect(dsl.caskroom_path).to eq(cask.caskroom_path)
  end

  it "supports the staged_path method" do
    expect(dsl.staged_path).to eq(cask.staged_path)
  end

  it "supports the appdir method" do
    expect(dsl.appdir).to eq(cask.appdir)
  end
end
