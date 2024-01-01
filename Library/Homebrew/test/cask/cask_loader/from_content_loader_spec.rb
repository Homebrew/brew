# frozen_string_literal: true

describe Cask::CaskLoader::FromContentLoader do
  alias_matcher :be_able_to_load, :be_can_load

  describe "::can_load?" do
    it "returns true for Casks specified with `cask \"token\" do … end`" do
      expect(described_class).to be_able_to_load <<~RUBY
        cask "token" do
        end
      RUBY
    end

    it "returns true for Casks specified with `cask \"token\" do; end`" do
      expect(described_class).to be_able_to_load <<~RUBY
        cask "token" do; end
      RUBY
    end

    it "returns true for Casks specified with `cask 'token' do … end`" do
      expect(described_class).to be_able_to_load <<~RUBY
        cask 'token' do
        end
      RUBY
    end

    it "returns true for Casks specified with `cask 'token' do; end`" do
      expect(described_class).to be_able_to_load <<~RUBY
        cask 'token' do; end
      RUBY
    end

    it "returns true for Casks specified with `cask(\"token\") { … }`" do
      expect(described_class).to be_able_to_load <<~RUBY
        cask("token") {
        }
      RUBY
    end

    it "returns true for Casks specified with `cask(\"token\") {}`" do
      expect(described_class).to be_able_to_load <<~RUBY
        cask("token") {}
      RUBY
    end

    it "returns true for Casks specified with `cask('token') { … }`" do
      expect(described_class).to be_able_to_load <<~RUBY
        cask('token') {
        }
      RUBY
    end

    it "returns true for Casks specified with `cask('token') {}`" do
      expect(described_class).to be_able_to_load <<~RUBY
        cask('token') {}
      RUBY
    end
  end
end
