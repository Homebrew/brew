# typed: true
# frozen_string_literal: true

require "livecheck/options"

RSpec.describe Homebrew::Livecheck::Options do
  subject(:options) { described_class }

  let(:cookies) { { "cookie_key" => "cookie_value" } }
  let(:header_string) { "Accept: */*" }
  let(:referer_url) { "https://example.com/referer" }
  let(:post_hash) do
    {
      empty:   "",
      boolean: "true",
      number:  "1",
      string:  "a + b = c",
    }
  end
  let(:args) do
    {
      compressed:    false,
      cookies:       cookies,
      header:        header_string,
      homebrew_curl: true,
      post_form:     post_hash,
      referer:       referer_url,
      user_agent:    :browser,
    }
  end
  let(:other_args) do
    {
      post_form: { something: "else" },
    }
  end
  # `post_form` and `post_json` are mutually exclusive
  let(:post_json_args) { args.except(:post_form).merge(post_json: post_hash) }
  let(:other_post_json_args) do
    {
      post_json: { something: "else" },
    }
  end
  let(:merged_hash) { args.merge(other_args) }
  let(:post_json_merged_hash) { post_json_args.merge(other_post_json_args) }
  let(:base_options) { options.new(**args) }
  let(:other_options) { options.new(**other_args) }
  let(:merged_options) { options.new(**merged_hash) }

  describe "#url_options" do
    it "returns a Hash of the options that are provided as arguments to the `url` DSL method" do
      expect(options.new.url_options).to eq({
        compressed:    nil,
        cookies:       nil,
        header:        nil,
        homebrew_curl: nil,
        post_form:     nil,
        post_json:     nil,
        referer:       nil,
        user_agent:    nil,
      })
    end
  end

  describe "#to_h" do
    it "returns a Hash of all instance variables" do
      # `T::Struct.serialize` omits `nil` values
      expect(options.new.to_h).to eq({})

      expect(options.new(**args).to_h).to eq(args)
    end
  end

  describe "#to_hash" do
    it "returns a Hash of all instance variables, using String keys" do
      # `T::Struct.serialize` omits `nil` values
      expect(options.new.to_hash).to eq({})

      expect(options.new(**args).to_hash).to eq(args.transform_keys(&:to_s))
    end
  end

  describe "#merge" do
    it "returns an Options object with merged values and doesn't modify `self`" do
      o1 = options.new(**args)
      expect(o1.merge(options.new(**other_post_json_args)))
        .to eq(options.new(**post_json_merged_hash))
      expect(o1).to eq(base_options)
    end
  end

  describe "#merge!" do
    it "merges values from `other` into `self` and returns `self`" do
      o1 = options.new(**args)
      expect(o1.merge!(other_options)).to eq(merged_options)
      expect(o1).to eq(merged_options)

      o2 = options.new(**args)
      expect(o2.merge!(base_options)).to eq(base_options)
      expect(o2).to eq(base_options)

      o3 = options.new(**args)
      expect(o3.merge!(options.new)).to eq(base_options)
      expect(o3).to eq(base_options)
    end

    it "unsets the opposite value when `other` sets `post_form` or `post_json`" do
      o1 = options.new(**args)
      expect(o1.merge!(options.new(**other_post_json_args))).to eq(options.new(**post_json_merged_hash))

      o2 = options.new(**post_json_args)
      expect(o2.merge!(other_options)).to eq(merged_options)
    end

    it "doesn't unset `post_form` or `post_json` when `other` sets neither" do
      o1 = options.new(**args)
      expect(o1.merge!(options.new(user_agent: :curl)))
        .to eq(options.new(**args, user_agent: :curl))
    end

    it "doesn't share a merged collection value with `other`" do
      o1 = options.new(**args)
      o1.merge!(other_options)
      o1.post_form = nil

      expect(other_options.post_form).to eq(other_args[:post_form])
    end

    it "raises an error if `other` sets both `post_form` and `post_json`" do
      o1 = options.new(**args)
      expect { o1.merge!(options.new(post_form: post_hash, post_json: post_hash)) }
        .to raise_error(ArgumentError, /both `post_form` and `post_json`/)
      expect(o1).to eq(base_options)

      o2 = options.new(post_form: post_hash, post_json: post_hash)
      expect { o2.merge!(options.new(post_form: post_hash, post_json: post_hash)) }
        .to raise_error(ArgumentError, /both `post_form` and `post_json`/)
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

    it "returns false if other object is not the same class" do
      expect(options.new == :other).to be false
    end
  end

  describe "#empty?" do
    specify do
      expect(options.new.empty?).to be true
      expect(options.new(**args).empty?).to be false
    end
  end

  describe "#present?" do
    specify do
      expect(options.new.present?).to be false
      expect(options.new(**args).present?).to be true
    end
  end
end
