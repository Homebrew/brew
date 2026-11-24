# typed: strict
# frozen_string_literal: true

require "utils/timer"

RSpec.describe Utils::Timer do
  describe "#remaining" do
    it "returns nil when nil" do
      expect(described_class.remaining(nil)).to be_nil
    end

    it "returns time remaining when there is time remaining" do
      expect(described_class.remaining(Time.now + 10)).to be > 1
    end

    it "returns 0 when there is no time remaining" do
      expect(described_class.remaining(Time.now - 10)).to be 0
    end
  end

  describe "#remaining!" do
    it "returns nil when nil" do
      expect(described_class.remaining!(nil)).to be_nil
    end

    it "returns time remaining when there is time remaining" do
      expect(described_class.remaining!(Time.now + 10)).to be > 1
    end

    it "returns 0 when there is no time remaining" do
      expect { described_class.remaining!(Time.now - 10) }.to raise_error(Timeout::Error)
    end

    it "raises Timeout::Error in a fresh process" do
      output = Utils.popen_read(
        *HOMEBREW_RUBY_EXEC_ARGS, "-I", $LOAD_PATH.join(File::PATH_SEPARATOR),
        "-rstandalone/sorbet", "-rutils/timer", "-e", <<~RUBY, err: :out
          begin
            Utils::Timer.remaining!(Time.now - 10)
          rescue Timeout::Error => e
            puts e.class
          end
        RUBY
      )

      expect(output).to eq("Timeout::Error\n")
    end
  end
end
