# typed: false
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/extract"
require "dependency_collector"

RSpec.describe Homebrew::DevCmd::Extract do
  it_behaves_like "parseable arguments"

  describe "#with_monkey_patch" do
    subject(:extract) do
      allow_any_instance_of(Homebrew::CLI::Parser).to receive(:check_named_args)
      described_class.new([])
    end

    it "makes method_missing a noop on BottleSpecification during the block and restores it after" do
      bs = BottleSpecification.new
      expect { bs.no_such_method }.to raise_error(NoMethodError)
      expect(BottleSpecification.private_instance_methods(false)).not_to include(:method_missing)
      extract.send(:with_monkey_patch) do
        expect { bs.no_such_method }.not_to raise_error
      end
      expect { bs.no_such_method }.to raise_error(NoMethodError)
      expect(BottleSpecification.private_instance_methods(false)).not_to include(:method_missing)
    end

    it "makes method_missing a noop on Resource during the block and restores it after" do
      resource = Resource.new
      expect { resource.no_such_method }.to raise_error(NoMethodError)
      expect(Resource.private_instance_methods(false)).not_to include(:method_missing)
      extract.send(:with_monkey_patch) do
        expect { resource.no_such_method }.not_to raise_error
      end
      expect { resource.no_such_method }.to raise_error(NoMethodError)
      expect(Resource.private_instance_methods(false)).not_to include(:method_missing)
    end

    it "makes parse_symbol_spec a noop on DependencyCollector during the block and restores it after" do
      dc = DependencyCollector.new
      expect(dc.send(:parse_symbol_spec, :macos, [])).to be_a(MacOSRequirement)
      extract.send(:with_monkey_patch) do
        expect(dc.send(:parse_symbol_spec, :macos, [])).to be_nil
      end
      expect(dc.send(:parse_symbol_spec, :macos, [])).to be_a(MacOSRequirement)
    end

    it "restores all methods even when the block raises" do
      dc = DependencyCollector.new
      resource = Resource.new
      expect { extract.send(:with_monkey_patch) { raise "oops" } }.to raise_error("oops")
      expect(dc.send(:parse_symbol_spec, :macos, [])).to be_a(MacOSRequirement)
      expect { resource.no_such_method }.to raise_error(NoMethodError)
    end

    it "restores a directly-defined method_missing on BottleSpecification if one exists" do
      sentinel = Object.new
      BottleSpecification.class_eval { private define_method(:method_missing) { |*_| sentinel } }
      begin
        extract.send(:with_monkey_patch) do
          expect(BottleSpecification.new.no_such_method).to be_nil
        end
        expect(BottleSpecification.new.no_such_method).to be(sentinel)
        expect(BottleSpecification.private_instance_methods(false)).to include(:method_missing)
      ensure
        BottleSpecification.remove_method(:method_missing)
      end
    end

    it "restores correctly across multiple sequential invocations" do
      dc = DependencyCollector.new
      2.times do
        extract.send(:with_monkey_patch) do
          expect(dc.send(:parse_symbol_spec, :macos, [])).to be_nil
        end
        expect(dc.send(:parse_symbol_spec, :macos, [])).to be_a(MacOSRequirement)
      end
    end
  end

  context "when extracting a formula" do
    let!(:target) do
      path = HOMEBREW_TAP_DIRECTORY/"homebrew/homebrew-foo"
      (path/"Formula").mkpath
      target = Tap.from_path(path)
      core_tap = CoreTap.instance
      core_tap.path.cd do
        system "git", "init"
        # Start with deprecated bottle syntax
        setup_test_formula "testball", bottle_block: <<~EOS

          bottle do
            cellar :any
          end
        EOS
        system "git", "add", "--all"
        system "git", "commit", "-m", "testball 0.1"
        # Replace with a valid formula for the next version
        formula_file = setup_test_formula "testball"
        contents = File.read(formula_file)
        contents.gsub!("testball-0.1", "testball-0.2")
        File.write(formula_file, contents)
        system "git", "add", "--all"
        system "git", "commit", "-m", "testball 0.2"
      end
      { name: target.name, path: }
    end

    it "retrieves the most recent version of formula", :integration_test do
      path = target[:path]/"Formula/testball@0.2.rb"
      expect { brew "extract", "testball", target[:name] }
        .to output(/^#{path}$/).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
      expect(path).to exist
      expect(Formulary.factory(path).version).to eq "0.2"
    end

    it "retrieves the specified version of formula", :integration_test do
      path = target[:path]/"Formula/testball@0.1.rb"
      expect { brew "extract", "testball", target[:name], "--version=0.1" }
        .to output(/^#{path}$/).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
      expect(path).to exist
      expect(Formulary.factory(path).version).to eq "0.1"
    end

    it "retrieves the compatible version of formula", :integration_test do
      path = target[:path]/"Formula/testball@0.rb"
      expect { brew "extract", "testball", target[:name], "--version=0" }
        .to output(/^#{path}$/).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
      expect(path).to exist
      expect(Formulary.factory(path).version).to eq "0.2"
    end
  end
end
