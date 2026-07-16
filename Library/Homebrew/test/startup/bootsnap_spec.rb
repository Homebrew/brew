# typed: strict
# frozen_string_literal: true

RSpec.describe Homebrew::Bootsnap do
  describe "::load!" do
    it "does not error when the configured gem path is unavailable" do
      with_env(HOMEBREW_BOOTSNAP_GEM_PATH: "#{TEST_TMPDIR}/missing-bootsnap", HOMEBREW_NO_BOOTSNAP: nil) do
        expect { described_class.load! }.not_to raise_error
      end
    end
  end

  describe "::prewarm!" do
    it "compiles caches for common command load graphs in a detached background process" do
      with_env(HOMEBREW_BOOTSNAP_GEM_PATH: "gem/path", HOMEBREW_NO_BOOTSNAP: nil, HOMEBREW_TESTS: nil) do
        expect(Process).to receive(:spawn).with(
          *HOMEBREW_RUBY_EXEC_ARGS, "-I", $LOAD_PATH.join(File::PATH_SEPARATOR),
          "-rglobal", "-rcmd/install", "-rcmd/fetch", "-rcmd/upgrade", "-e", "",
          hash_including(pgroup: true)
        ).and_return(12345)
        expect(Process).to receive(:detach).with(12345)

        described_class.prewarm!
      end
    end

    it "does nothing when Bootsnap is disabled" do
      with_env(HOMEBREW_BOOTSNAP_GEM_PATH: "gem/path", HOMEBREW_NO_BOOTSNAP: "1", HOMEBREW_TESTS: nil) do
        expect(Process).not_to receive(:spawn)

        described_class.prewarm!
      end
    end

    it "does not error when starting the prewarm process fails" do
      with_env(HOMEBREW_BOOTSNAP_GEM_PATH: "gem/path", HOMEBREW_NO_BOOTSNAP: nil, HOMEBREW_TESTS: nil) do
        expect(Process).to receive(:spawn).and_raise(Errno::EAGAIN)
        expect(Process).not_to receive(:detach)

        expect { described_class.prewarm! }.not_to raise_error
      end
    end

    it "does not error when detaching the prewarm process fails" do
      with_env(HOMEBREW_BOOTSNAP_GEM_PATH: "gem/path", HOMEBREW_NO_BOOTSNAP: nil, HOMEBREW_TESTS: nil) do
        expect(Process).to receive(:spawn).and_return(12345)
        expect(Process).to receive(:detach).with(12345).and_raise(Errno::ECHILD)

        expect { described_class.prewarm! }.not_to raise_error
      end
    end

    it "does nothing in tests" do
      with_env(HOMEBREW_BOOTSNAP_GEM_PATH: "gem/path", HOMEBREW_NO_BOOTSNAP: nil, HOMEBREW_TESTS: "1") do
        expect(Process).not_to receive(:spawn)

        described_class.prewarm!
      end
    end
  end
end
