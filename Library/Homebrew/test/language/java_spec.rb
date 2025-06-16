# frozen_string_literal: true

require "language/java"

RSpec.describe Language::Java do
  let(:f) do
    formula("openjdk") do
      url "openjdk"
      version "15.0.1"
    end
  end

  let(:expected_home) do
    if OS.mac?
      f.opt_libexec/"openjdk.jdk/Contents/Home"
    else
      f.opt_libexec
    end
  end

  before do
    allow(Formula).to receive(:[]).and_return(f)
    allow(f).to receive_messages(any_version_installed?: true, any_installed_version: f.version)
  end

  describe "::java_home" do
    it "returns valid JAVA_HOME if version is specified" do
      java_home = described_class.java_home("1.8+")
      expect(java_home).to eql(expected_home)
    end

    it "returns valid JAVA_HOME if version is not specified" do
      java_home = described_class.java_home
      expect(java_home).to eql(expected_home)
    end
  end

  describe "::java_home_env" do
    it "returns java_home path if version specified" do
      java_home_env = described_class.java_home_env("1.8+")
      expect(java_home_env[:JAVA_HOME]).to eql(expected_home.to_s)
    end

    it "returns java_home path if version is not specified" do
      java_home_env = described_class.java_home_env
      expect(java_home_env[:JAVA_HOME]).to eql(expected_home.to_s)
    end
  end

  describe "::overridable_java_home_env" do
    it "returns java_home path if version specified" do
      overridable_java_home_env = described_class.overridable_java_home_env("1.8+")
      expect(overridable_java_home_env[:JAVA_HOME]).to eql("${JAVA_HOME:-#{expected_home}}")
    end

    it "returns java_home path if version is not specified" do
      overridable_java_home_env = described_class.overridable_java_home_env
      expect(overridable_java_home_env[:JAVA_HOME]).to eql("${JAVA_HOME:-#{expected_home}}")
    end
  end
end
