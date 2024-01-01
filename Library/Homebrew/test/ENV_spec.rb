# frozen_string_literal: true

require "extend/ENV"

describe "ENV" do
  shared_examples EnvActivation do
    subject(:env) { env_activation.extend(described_class) }

    let(:env_activation) { {}.extend(EnvActivation) }

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

      # NOTE: this may be a wrong behavior; we should probably reject objects that
      # do not respond to #to_str. For now this documents existing behavior.
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
        subject.public_send(:"gcc-6")
        expect(subject.compiler).to eq("gcc-6")
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

      it "leaves non-sensitive environment variables alone" do
        subject["FOO"] = "bar"
        subject.clear_sensitive_environment!
        expect(subject["FOO"]).to eq "bar"
      end
    end

    describe "#compiler_any_clang?" do
      it "returns true for llvm_clang" do
        expect(subject.compiler_any_clang?(:llvm_clang)).to be true
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
      it "supports gcc-5" do
        env["HOMEBREW_CC"] = "gcc-5"
        env.cxx11
        expect(env["HOMEBREW_CCCFG"]).to include("x")
      end

      example "supports gcc-6" do
        env["HOMEBREW_CC"] = "gcc-6"
        env.cxx11
        expect(env["HOMEBREW_CCCFG"]).to include("x")
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
  end
end
