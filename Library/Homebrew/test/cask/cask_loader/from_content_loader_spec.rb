# frozen_string_literal: true

RSpec.describe Cask::CaskLoader::FromContentLoader do
  describe "::try_new" do
    it "returns a loader for Casks specified with `cask \"token\" do … end`" do
      expect(described_class.try_new(<<~RUBY)).not_to be_nil
        cask "token" do
        end
      RUBY
    end

    it "returns a loader for Casks specified with `cask \"token\" do; end`" do
      expect(described_class.try_new(<<~RUBY)).not_to be_nil
        cask "token" do; end
      RUBY
    end

    it "returns a loader for Casks specified with `cask 'token' do … end`" do
      expect(described_class.try_new(<<~RUBY)).not_to be_nil
        cask 'token' do
        end
      RUBY
    end

    it "returns a loader for Casks specified with `cask 'token' do; end`" do
      expect(described_class.try_new(<<~RUBY)).not_to be_nil
        cask 'token' do; end
      RUBY
    end

    it "returns a loader for Casks specified with `cask(\"token\") { … }`" do
      expect(described_class.try_new(<<~RUBY)).not_to be_nil
        cask("token") {
        }
      RUBY
    end

    it "returns a loader for Casks specified with `cask(\"token\") {}`" do
      expect(described_class.try_new(<<~RUBY)).not_to be_nil
        cask("token") {}
      RUBY
    end

    it "returns a loader for Casks specified with `cask('token') { … }`" do
      expect(described_class.try_new(<<~RUBY)).not_to be_nil
        cask('token') {
        }
      RUBY
    end

    it "returns a loader for Casks specified with `cask('token') {}`" do
      expect(described_class.try_new(<<~RUBY)).not_to be_nil
        cask('token') {}
      RUBY
    end
  end
end
