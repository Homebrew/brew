# frozen_string_literal: true

require "bundle"
require "bundle/brewfile"

RSpec.describe Homebrew::Bundle::Brewfile do
  describe "path" do
    subject(:path) do
      described_class.path(dash_writes_to_stdout:, global: has_global, file: file_value)
    end

    let(:dash_writes_to_stdout) { false }
    let(:env_bundle_file_global_value) { nil }
    let(:env_bundle_file_value) { nil }
    let(:env_user_config_home_value) { "/Users/username/.homebrew" }
    let(:env_home_value) { "/Users/username" }
    let(:file_value) { nil }
    let(:has_global) { false }
    let(:config_dir_exist) { false }
    let(:config_dir_brewfile_exist) { false }
    let(:home_dir_brewfile_exist) { false }

    before do
      allow(ENV).to receive(:fetch).and_return(nil)
      allow(ENV).to receive(:fetch).with("HOMEBREW_BUNDLE_FILE_GLOBAL", any_args)
                                   .and_return(env_bundle_file_global_value)
      allow(ENV).to receive(:fetch).with("HOMEBREW_BUNDLE_FILE", any_args)
                                   .and_return(env_bundle_file_value)

      allow(ENV).to receive(:fetch).with("HOMEBREW_USER_CONFIG_HOME", any_args)
                                   .and_return(env_user_config_home_value)
      allow(File).to receive(:exist?).with("/Users/username/.homebrew/Brewfile")
                                     .and_return(config_dir_brewfile_exist)
      allow(File).to receive(:exist?).with("/Users/username/.Brewfile")
                                     .and_return(home_dir_brewfile_exist)
      allow(Dir).to receive(:home).and_return(env_home_value)
      allow(Dir).to receive(:exist?).with("/Users/username/.homebrew")
                                    .and_return(config_dir_exist)
    end

    context "when `file` is specified with a relative path" do
      let(:file_value) { "path/to/Brewfile" }
      let(:expected_pathname) { Pathname.new(file_value).expand_path(Dir.pwd) }

      it "returns the expected path" do
        expect(path).to eq(expected_pathname)
      end

      context "with a configured HOMEBREW_BUNDLE_FILE" do
        let(:env_bundle_file_value) { "/path/to/Brewfile" }

        it "returns the value specified by `file` path" do
          expect(path).to eq(expected_pathname)
        end
      end

      context "with an empty HOMEBREW_BUNDLE_FILE" do
        let(:env_bundle_file_value) { "" }

        it "returns the value specified by `file` path" do
          expect(path).to eq(expected_pathname)
        end
      end
    end

    context "when `file` is specified with an absolute path" do
      let(:file_value) { "/tmp/random_file" }
      let(:expected_pathname) { Pathname.new(file_value) }

      it "returns the expected path" do
        expect(path).to eq(expected_pathname)
      end

      context "with a configured HOMEBREW_BUNDLE_FILE" do
        let(:env_bundle_file_value) { "/path/to/Brewfile" }

        it "returns the value specified by `file` path" do
          expect(path).to eq(expected_pathname)
        end
      end

      context "with an empty HOMEBREW_BUNDLE_FILE" do
        let(:env_bundle_file_value) { "" }

        it "returns the value specified by `file` path" do
          expect(path).to eq(expected_pathname)
        end
      end
    end

    context "when `file` is specified with `-`" do
      let(:file_value) { "-" }
      let(:expected_pathname) { Pathname.new("/dev/stdin") }

      it "returns stdin by default" do
        expect(path).to eq(expected_pathname)
      end

      context "with a configured HOMEBREW_BUNDLE_FILE" do
        let(:env_bundle_file_value) { "/path/to/Brewfile" }

        it "returns the value specified by `file` path" do
          expect(path).to eq(expected_pathname)
        end
      end

      context "with an empty HOMEBREW_BUNDLE_FILE" do
        let(:env_bundle_file_value) { "" }

        it "returns the value specified by `file` path" do
          expect(path).to eq(expected_pathname)
        end
      end

      context "when `dash_writes_to_stdout` is true" do
        let(:expected_pathname) { Pathname.new("/dev/stdout") }
        let(:dash_writes_to_stdout) { true }

        it "returns stdout" do
          expect(path).to eq(expected_pathname)
        end

        context "with a configured HOMEBREW_BUNDLE_FILE" do
          let(:env_bundle_file_value) { "/path/to/Brewfile" }

          it "returns the value specified by `file` path" do
            expect(path).to eq(expected_pathname)
          end
        end

        context "with an empty HOMEBREW_BUNDLE_FILE" do
          let(:env_bundle_file_value) { "" }

          it "returns the value specified by `file` path" do
            expect(path).to eq(expected_pathname)
          end
        end
      end
    end

    context "when `global` is true" do
      let(:has_global) { true }
      let(:expected_pathname) { Pathname.new("#{Dir.home}/.Brewfile") }

      it "returns the expected path" do
        expect(path).to eq(expected_pathname)
      end

      context "when HOMEBREW_BUNDLE_FILE_GLOBAL is set" do
        let(:env_bundle_file_global_value) { "/path/to/Brewfile" }
        let(:expected_pathname) { Pathname.new(env_bundle_file_global_value) }

        it "returns the value specified by the environment variable" do
          expect(path).to eq(expected_pathname)
        end
      end

      context "when HOMEBREW_BUNDLE_FILE is set" do
        let(:env_bundle_file_value) { "/path/to/Brewfile" }

        it "returns the value specified by the variable" do
          expect { path }.to raise_error(RuntimeError)
        end
      end

      context "when HOMEBREW_BUNDLE_FILE is `` (empty)" do
        let(:env_bundle_file_value) { "" }

        it "returns the value specified by `file` path" do
          expect(path).to eq(expected_pathname)
        end
      end

      context "when HOMEBREW_USER_CONFIG_HOME/Brewfile exists" do
        let(:config_dir_brewfile_exist) { true }
        let(:config_dir_exist) { true }
        let(:home_dir_brewfile_exist) { true }
        let(:expected_pathname) { Pathname.new("#{env_user_config_home_value}/Brewfile") }

        it "returns the expected path" do
          expect(path).to eq(expected_pathname)
        end
      end

      context "when empty HOMEBREW_USER_CONFIG_HOME exists, and .Brewfile does not" do
        let(:config_dir_exist) { true }
        let(:expected_pathname) { Pathname.new("#{env_user_config_home_value}/Brewfile") }

        it "returns the expected path" do
          expect(path).to eq(expected_pathname)
        end
      end

      context "when empty HOMEBREW_USER_CONFIG_HOME and .Brewfile exist" do
        let(:config_dir_exist) { true }
        let(:home_dir_brewfile_exist) { true }
        let(:expected_pathname) { Pathname.new("#{env_home_value}/.Brewfile") }

        it "returns the expected path" do
          expect(path).to eq(expected_pathname)
        end
      end
    end

    context "when HOMEBREW_BUNDLE_FILE has a value" do
      let(:env_bundle_file_value) { "/path/to/Brewfile" }

      it "returns the expected path" do
        expect(path).to eq(Pathname.new(env_bundle_file_value))
      end

      describe "that is `` (empty)" do
        let(:env_bundle_file_value) { "" }

        it "defaults to `${PWD}/Brewfile`" do
          expect(path).to eq(Pathname.new("Brewfile").expand_path(Dir.pwd))
        end
      end

      describe "that is `nil`" do
        let(:env_bundle_file_value) { nil }

        it "defaults to `${PWD}/Brewfile`" do
          expect(path).to eq(Pathname.new("Brewfile").expand_path(Dir.pwd))
        end
      end
    end
  end
end
