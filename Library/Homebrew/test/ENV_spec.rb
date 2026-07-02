# typed: true
# frozen_string_literal: true

require "extend/ENV"

RSpec.describe "ENV" do
  subject(:env) { {}.extend(EnvActivation).extend(described_class) }

  shared_examples EnvActivation do
    include Context

    it "supports switching compilers" do
      subject.clang
      expect(subject["LD"]).to be_nil
      expect(subject["CC"]).to eq(subject["OBJC"])
    end

    describe "#with_build_environment" do
      it "restores the environment" do
        before = subject.dup

        subject.with_build_environment do
          subject["foo"] = "bar"
        end

        expect(subject["foo"]).to be_nil
        expect(subject).to eq(before)
      end

      it "ensures the environment is restored" do
        before = subject.dup

        expect do
          subject.with_build_environment do
            subject["foo"] = "bar"
            raise StandardError
          end
        end.to raise_error(StandardError)

        expect(subject["foo"]).to be_nil
        expect(subject).to eq(before)
      end

      it "returns the value of the block" do
        expect(subject.with_build_environment { 1 }).to eq(1)
      end

      it "does not mutate the interface" do
        expected = subject.methods

        subject.with_build_environment do
          expect(subject.methods).to eq(expected)
        end

        expect(subject.methods).to eq(expected)
      end
    end

    describe "#append" do
      it "appends to an existing key" do
        subject["foo"] = "bar"
        subject.append "foo", "1"
        expect(subject["foo"]).to eq("bar 1")
      end

      it "appends to an existing empty key" do
        subject["foo"] = ""
        subject.append "foo", "1"
        expect(subject["foo"]).to eq("1")
      end

      it "appends to a non-existent key" do
        subject.append "foo", "1"
        expect(subject["foo"]).to eq("1")
      end

      # NOTE: This may be a wrong behavior; we should probably reject objects that
      #       do not respond to `#to_str`. For now this documents existing behavior.
      it "coerces a value to a string" do
        subject.append "foo", 42
        expect(subject["foo"]).to eq("42")
      end
    end

    describe "#prepend" do
      it "prepends to an existing key" do
        subject["foo"] = "bar"
        subject.prepend "foo", "1"
        expect(subject["foo"]).to eq("1 bar")
      end

      it "prepends to an existing empty key" do
        subject["foo"] = ""
        subject.prepend "foo", "1"
        expect(subject["foo"]).to eq("1")
      end

      it "prepends to a non-existent key" do
        subject.prepend "foo", "1"
        expect(subject["foo"]).to eq("1")
      end

      # NOTE: this may be a wrong behavior; we should probably reject objects that
      # do not respond to #to_str. For now this documents existing behavior.
      it "coerces a value to a string" do
        subject.prepend "foo", 42
        expect(subject["foo"]).to eq("42")
      end
    end

    describe "#append_path" do
      it "appends to a path" do
        subject.append_path "FOO", "/usr/bin"
        expect(subject["FOO"]).to eq("/usr/bin")

        subject.append_path "FOO", "/bin"
        expect(subject["FOO"]).to eq("/usr/bin#{File::PATH_SEPARATOR}/bin")
      end
    end

    describe "#prepend_path" do
      it "prepends to a path" do
        subject.prepend_path "FOO", "/usr/local"
        expect(subject["FOO"]).to eq("/usr/local")

        subject.prepend_path "FOO", "/usr"
        expect(subject["FOO"]).to eq("/usr#{File::PATH_SEPARATOR}/usr/local")
      end
    end

    describe "#compiler" do
      it "allows switching compilers" do
        subject.public_send(:"gcc-9")
        expect(subject.compiler).to eq("gcc-9")
      end
    end

    example "deparallelize_block_form_restores_makeflags" do
      subject["MAKEFLAGS"] = "-j4"

      subject.deparallelize do
        expect(subject["MAKEFLAGS"]).to be_nil
      end

      expect(subject["MAKEFLAGS"]).to eq("-j4")
    end

    describe "#sensitive_environment" do
      it "list sensitive environment" do
        subject["SECRET_TOKEN"] = "password"
        expect(subject.sensitive_environment).to include("SECRET_TOKEN")
      end
    end

    describe "#clear_sensitive_environment!" do
      it "removes sensitive environment variables" do
        subject["SECRET_TOKEN"] = "password"
        subject.clear_sensitive_environment!
        expect(subject).not_to include("SECRET_TOKEN")
      end

      it "preserves excepted sensitive environment variables" do
        subject["SECRET_TOKEN"] = "password"
        subject.clear_sensitive_environment!(except: ["SECRET_TOKEN"])
        expect(subject["SECRET_TOKEN"]).to eq("password")
      end

      it "leaves non-sensitive environment variables alone" do
        subject["FOO"] = "bar"
        subject.clear_sensitive_environment!
        expect(subject["FOO"]).to eq "bar"
      end

      it "restores the environment after yielding" do
        subject["SECRET_TOKEN"] = "password"
        subject["FOO"] = "bar"

        result = subject.clear_sensitive_environment! do
          subject["FOO"] = "baz"
          subject["OTHER_TOKEN"] = "secret"

          [subject["SECRET_TOKEN"], subject["FOO"]]
        end

        expect(result).to eq([nil, "baz"])
        expect(subject["SECRET_TOKEN"]).to eq("password")
        expect(subject["FOO"]).to eq("bar")
        expect(subject).not_to include("OTHER_TOKEN")
      end
    end

    describe "#clear_sensitive_environment_for_eval!" do
      it "defers HOMEBREW_ secrets to a placeholder" do
        subject["HOMEBREW_PRIVATE_TOKEN"] = "glpat-secret"

        deferred = subject.clear_sensitive_environment_for_eval! { subject["HOMEBREW_PRIVATE_TOKEN"] }

        expect(deferred).not_to eq("glpat-secret")
        expect(deferred).not_to be_empty
        expect(subject.expand_deferred_environment("PRIVATE-TOKEN: #{deferred}")).to eq("PRIVATE-TOKEN: #{deferred}")
      end

      it "never expands a non-HOMEBREW_ secret back to its real value" do
        subject["SECRET_TOKEN"] = "password"
        deferred = subject.clear_sensitive_environment_for_eval! { subject["SECRET_TOKEN"] }

        with_context(deferred_environment_expansion: true) do
          expect(subject.expand_deferred_environment("X: #{deferred}")).not_to include("password")
        end
      end

      it "keeps HOMEBREW_GITHUB_API_TOKEN readable during eval" do
        subject["HOMEBREW_GITHUB_API_TOKEN"] = "gh-token"
        expect(subject.clear_sensitive_environment_for_eval! do
          subject["HOMEBREW_GITHUB_API_TOKEN"]
        end).to eq("gh-token")
      end

      it "restores the environment after yielding" do
        subject["HOMEBREW_PRIVATE_TOKEN"] = "glpat-secret"
        subject.clear_sensitive_environment_for_eval! { nil }
        expect(subject["HOMEBREW_PRIVATE_TOKEN"]).to eq("glpat-secret")
      end
    end

    describe "#expand_deferred_environment" do
      it "leaves values without a deferred placeholder unchanged" do
        expect(subject.expand_deferred_environment("PRIVATE-TOKEN: plain")).to eq("PRIVATE-TOKEN: plain")
      end

      it "expands placeholders only during download strategy fetches" do
        subject["HOMEBREW_PRIVATE_TOKEN"] = "glpat-secret"
        deferred = subject.clear_sensitive_environment_for_eval! { subject["HOMEBREW_PRIVATE_TOKEN"] }

        with_context(deferred_environment_expansion: true) do
          expect(subject.expand_deferred_environment("PRIVATE-TOKEN: #{deferred}"))
            .to eq("PRIVATE-TOKEN: glpat-secret")
        end
      end
    end
  end

  describe Stdenv do
    include_examples EnvActivation
  end

  describe Superenv do
    include_examples EnvActivation

    it "initializes deps" do
      expect(env.deps).to eq([])
      expect(env.keg_only_deps).to eq([])
    end

    describe "#cxx11" do
      it "supports gcc-11" do
        env["HOMEBREW_CC"] = "gcc-11"
        env.cxx11
        expect(env["HOMEBREW_CCCFG"]).to include("x")
        expect(env["HOMEBREW_CCCFG"]).not_to include("g")
      end

      it "supports clang" do
        env["HOMEBREW_CC"] = "clang"
        env.cxx11
        expect(env["HOMEBREW_CCCFG"]).to include("x")
        expect(env["HOMEBREW_CCCFG"]).to include("g")
      end
    end

    describe "#set_debug_symbols" do
      it "sets the debug symbols flag" do
        env.set_debug_symbols
        expect(env["HOMEBREW_CCCFG"]).to include("D")
      end
    end

    describe "#llvm_clang" do
      before { env.llvm_clang }

      it "sets HOMEBREW_CC to shim name" do
        expect(env["HOMEBREW_CC"]).to eq "llvm_clang"
      end

      it "sets CC/CXX to real names" do
        expect(env["CC"]).to eq "clang"
        expect(env["CXX"]).to eq "clang++"
        expect(env["OBJC"]).to eq "clang"
        expect(env["OBJCXX"]).to eq "clang++"
      end
    end

    describe "when using versioned GCC" do
      let(:gcc) { "gcc-#{CompilerConstants::GNU_GCC_VERSIONS.last}" }

      before { env.method(gcc).call }

      it "sets versioned HOMEBREW_CC" do
        expect(env["HOMEBREW_CC"]).to eq gcc
      end

      it "sets unversioned CC/CXX on Linux", :needs_linux do
        expect(env["CC"]).to eq "gcc"
        expect(env["CXX"]).to eq "g++"
        expect(env["OBJC"]).to eq "gcc"
        expect(env["OBJCXX"]).to eq "g++"
      end

      # We keep versioned name on macOS as /usr/bin/gcc is Clang which may not
      # be compatible with binaries created with GCC, e.g. if using libstdc++.
      it "sets versioned CC/CXX on macOS", :needs_macos do
        expect(env["CC"]).to eq gcc
        expect(env["CXX"]).to eq gcc.sub("gcc", "g++")
        expect(env["OBJC"]).to eq gcc
        expect(env["OBJCXX"]).to eq gcc.sub("gcc", "g++")
      end
    end
  end
end
