# typed: strict
# frozen_string_literal: true

require "extend/pathname"

RSpec.describe Pathname do
  describe ".write_env_script" do
    it "creates script with arguments" do
      mktmpdir do |tmpdir|
        (tmpdir/"wrapper_script").write_env_script tmpdir/"test", ["foo", "bar"], TEST: "baz"
        expect((tmpdir/"wrapper_script").read).to eq(<<~BASH)
          #!/bin/bash
          TEST="baz" exec "#{tmpdir}/test" foo bar "$@"
        BASH
      end
    end

    it "creates script without arguments" do
      mktmpdir do |tmpdir|
        env = { TEST: "bar" }
        env["TEST2"] = tmpdir/"baz"
        (tmpdir/"wrapper_script").write_env_script "test", env
        expect((tmpdir/"wrapper_script").read).to eq(<<~BASH)
          #!/bin/bash
          TEST="bar" TEST2="#{tmpdir}/baz" exec "test"  "$@"
        BASH
      end
    end
  end

  describe ".env_script_all_files" do
    it "create scipts for files" do
      mktmpdir do |input_dir|
        FileUtils.touch input_dir/"foo"
        FileUtils.touch input_dir/"bar"

        mktmpdir do |output_dir|
          input_dir.env_script_all_files(output_dir, FOO: "foo", BAR: input_dir/"test")

          expect((input_dir/"foo").read).to eq(<<~BASH)
            #!/bin/bash
            FOO="foo" BAR="#{input_dir}/test" exec "#{output_dir}/foo"  "$@"
          BASH

          expect((input_dir/"bar").read).to eq(<<~BASH)
            #!/bin/bash
            FOO="foo" BAR="#{input_dir}/test" exec "#{output_dir}/bar"  "$@"
          BASH
        end
      end
    end

    it "raises an exception when file already exists" do
      mktmpdir do |input_dir|
        FileUtils.touch input_dir/"foo"

        mktmpdir do |output_dir|
          FileUtils.touch output_dir/"foo"
          expect { input_dir.env_script_all_files(output_dir, FOO: "foo") }.to raise_error(Errno::EEXIST)
        end
      end
    end
  end
end
