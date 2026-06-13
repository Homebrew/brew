# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/deadcode"

RSpec.describe Homebrew::DevCmd::Deadcode do
  let(:deadcode) { described_class.new([]) }

  it_behaves_like "parseable arguments"

  describe "#dead_code_locations" do
    let(:spoom_output) do
      <<~OUTPUT
        Candidates:
          Foo::Bar#qux cmd/foo.rb:20:2-22:5
          Foo::Bar#baz cmd/foo.rb:10:2-12:5
          Other#thing cmd/bar.rb:5:0-7:3

          Found 3 dead candidates
      OUTPUT
    end

    it "returns locations ordered from the bottom of each file upwards" do
      allow(Utils).to receive(:popen_read).and_return(spoom_output)

      expect(deadcode.send(:dead_code_locations))
        .to eq(["cmd/foo.rb:20:2-22:5", "cmd/foo.rb:10:2-12:5", "cmd/bar.rb:5:0-7:3"])
    end
  end

  describe "#remove" do
    it "removes each location in order" do
      removed = []
      allow(Utils).to receive(:safe_popen_read) { |*args, **| removed << args.last }

      deadcode.send(:remove, ["cmd/foo.rb:20:2-22:5", "cmd/bar.rb:5:0-7:3"])

      expect(removed).to eq(["cmd/foo.rb:20:2-22:5", "cmd/bar.rb:5:0-7:3"])
    end

    it "skips locations Spoom fails to remove without raising" do
      allow(Utils).to receive(:safe_popen_read) do |*args, **|
        raise ErrorDuringExecution.new(args, status: 1) if args.last == "cmd/foo.rb:10:2-12:5"
      end

      expect { deadcode.send(:remove, ["cmd/foo.rb:10:2-12:5"]) }
        .to output(%r{  cmd/foo\.rb:10:2-12:5}).to_stdout
    end
  end

  describe "#persisted?" do
    let(:file) { Tempfile.new(["deadcode", ".rb"]) }

    after { file.unlink }

    def location_for(content, needle)
      file.write(content)
      file.flush
      line = T.must(content.lines.index { |l| l.include?(needle) }) + 1
      "#{file.path}:#{line}:0-#{line}:3"
    end

    it "keeps definitions documented as `@api internal`" do
      content = "# @api internal\ndef self.foo; end\n"
      expect(deadcode.send(:persisted?, location_for(content, "def self.foo"))).to be(true)
    end

    it "keeps definitions documented as `@api public`" do
      content = "# @api public\ndef self.foo; end\n"
      expect(deadcode.send(:persisted?, location_for(content, "def self.foo"))).to be(true)
    end

    it "keeps definitions with an `override` signature" do
      content = "sig { override.void }\ndef foo; end\n"
      expect(deadcode.send(:persisted?, location_for(content, "def foo"))).to be(true)
    end

    it "keeps definitions marked `# deadcode:keep`" do
      content = "# deadcode:keep\ndef foo; end\n"
      expect(deadcode.send(:persisted?, location_for(content, "def foo"))).to be(true)
    end

    it "keeps definitions whose body is deprecated with `odeprecated`" do
      content = "def foo\n  odeprecated \"Foo.foo\"\nend\n"
      file.write(content)
      file.flush
      expect(deadcode.send(:persisted?, "#{file.path}:1:0-3:3")).to be(true)
    end

    it "keeps definitions matched by a `# deadcode:keep-matching` directive" do
      content = "# deadcode:keep-matching ^audit_\n\ndef audit_thing; end\n"
      file.write(content)
      file.flush
      expect(deadcode.send(:persisted?, "#{file.path}:3:0-3:3")).to be(true)
    end

    it "does not keep undocumented definitions" do
      content = "# An ordinary comment.\ndef foo; end\n"
      expect(deadcode.send(:persisted?, location_for(content, "def foo"))).to be(false)
    end
  end
end
