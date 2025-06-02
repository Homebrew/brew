# frozen_string_literal: true

require "build_environment"

RSpec.describe BuildEnvironment do
  let(:env) { described_class.new }

  describe "#<<" do
    it "returns itself" do
      expect(env << :foo).to be env
    end
  end

  describe "#merge" do
    it "returns itself" do
      expect(env.merge([])).to be env
    end
  end

  describe "#std?" do
    it "returns true if the environment contains :std" do
      env << :std
      expect(env).to be_std
    end

    it "returns false if the environment does not contain :std" do
      expect(env).not_to be_std
    end
  end

  describe BuildEnvironment::DSL do
    let(:build_environment_dsl) do
      klass = described_class
      Class.new do
        extend(klass)
      end
    end

    context "with a single argument" do
      subject(:build_env) do
        Class.new(build_environment_dsl) do
          env :std
        end
      end

      it(:env) { expect(build_env.env).to be_std }
    end
  end
end
