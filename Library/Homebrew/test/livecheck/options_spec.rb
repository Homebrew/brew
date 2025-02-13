# frozen_string_literal: true

require "livecheck/options"

RSpec.describe Homebrew::Livecheck::Options do
  subject(:options) { described_class }

  let(:post_hash) do
    {
      "empty"   => "",
      "boolean" => "true",
      "number"  => "1",
      "string"  => "a + b = c",
    }
  end
  let(:args) do
    {
      homebrew_curl: true,
      post_form:     post_hash,
      post_json:     post_hash,
    }
  end
  let(:other_args) do
    {
      post_form: { "something" => "else" },
    }
  end
  let(:merged_hash) { args.merge(other_args) }

  describe "#url_options" do
    it "returns a Hash of the options that are provided as arguments to the `url` DSL method" do
      expect(options.new.url_options).to eq({
        homebrew_curl: nil,
        post_form:     nil,
        post_json:     nil,
      })
    end
  end

  describe "#to_h" do
    it "returns a Hash of all instance variables" do
      expect(options.new.to_h).to eq({
        homebrew_curl: nil,
        post_form:     nil,
        post_json:     nil,
      })
    end
  end

  describe "#to_hash" do
    it "returns a Hash of all instance variables, using String keys" do
      expect(options.new.to_hash).to eq({
        "homebrew_curl" => nil,
        "post_form"     => nil,
        "post_json"     => nil,
      })
    end
  end

  describe "#merge" do
    it "returns an Options object with merged values" do
      expect(options.new(**args).merge(other_args))
        .to eq(options.new(**merged_hash))
      expect(options.new(**args).merge(options.new(**other_args)))
        .to eq(options.new(**merged_hash))
      expect(options.new(**args).merge(args))
        .to eq(options.new(**args))
    end
  end

  describe "#==" do
    it "returns true if all instance variables are the same" do
      obj_with_args1 = options.new(**args)
      obj_with_args2 = options.new(**args)
      expect(obj_with_args1 == obj_with_args2).to be true

      default_obj1 = options.new
      default_obj2 = options.new
      expect(default_obj1 == default_obj2).to be true
    end

    it "returns false if any instance variables differ" do
      expect(options.new == options.new(**args)).to be false
    end
  end

  describe "#empty?" do
    it "returns true if object has only default values" do
      expect(options.new.empty?).to be true
    end

    it "returns false if object has any non-default values" do
      expect(options.new(**args).empty?).to be false
    end
  end

  describe "#present?" do
    it "returns false if object has only default values" do
      expect(options.new.present?).to be false
    end

    it "returns true if object has any non-default values" do
      expect(options.new(**args).present?).to be true
    end
  end
end
