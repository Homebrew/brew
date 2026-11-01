# typed: true
# frozen_string_literal: true

require "bundle/dumper"

RSpec.shared_examples "a checked inventory" do |inventory_method = nil, empty_output: "", empty_inventory: [],
                                               stderr_forwarded: false|
  let(:inventory_output) { super() }
  let(:inventory_records) { super() }

  let(:inventory_executable) { mktmpdir/"example-tool" }

  def write_inventory(output: "", status: 0)
    inventory_executable.write <<~SH
      #!/bin/sh
      printf '%s' #{output.shellescape}
      printf '%s\\n' 'inventory diagnostic' >&2
      exit #{status}
    SH
    inventory_executable.chmod 0755
  end

  before do
    described_class.reset!
    write_inventory(output: inventory_output)
    allow(described_class).to receive(:package_manager_executable).and_return(inventory_executable)
  end

  after do
    described_class.reset!
  end

  it "parses only stdout" do
    expect(described_class.public_send(inventory_method)).to match(inventory_records)
  end

  it "preserves the command's successful stderr policy" do
    if stderr_forwarded
      expect { described_class.public_send(inventory_method) }.to output(/inventory diagnostic/).to_stderr
    else
      expect { described_class.public_send(inventory_method) }.not_to output.to_stderr
    end
  end

  it "rejects failed empty output" do
    write_inventory(status: 2)
    expect { described_class.public_send(inventory_method) }.to raise_error(ErrorDuringExecution)
  end

  it "retries failed inventory without reset" do
    write_inventory(status: 2)
    expect { described_class.public_send(inventory_method) }.to raise_error(ErrorDuringExecution)
    write_inventory(output: inventory_output)

    expect(described_class.public_send(inventory_method)).to match(inventory_records)
  end

  it "caches accepted inventory" do
    described_class.public_send(inventory_method)
    write_inventory(status: 2)

    expect(described_class.public_send(inventory_method)).to match(inventory_records)
  end

  it "caches a successful empty inventory" do
    write_inventory(output: empty_output)
    described_class.public_send(inventory_method)
    write_inventory(status: 2)

    expect(described_class.public_send(inventory_method)).to eq(empty_inventory)
  end

  it "queries again after reset" do
    described_class.public_send(inventory_method)
    write_inventory(output: empty_output)
    described_class.reset!

    expect(described_class.public_send(inventory_method)).to eq(empty_inventory)
  end

  it "rejects failed partial inventory with diagnostics" do
    write_inventory(output: inventory_output, status: 2)
    expect { described_class.public_send(inventory_method) }
      .to raise_error(ErrorDuringExecution, /exited with 2.*inventory diagnostic/m)
  end

  it "rejects termination by signal" do
    inventory_executable.write "#!/bin/sh\nkill -TERM $$\n"
    expect { described_class.public_send(inventory_method) }.to raise_error(ErrorDuringExecution)
  end
end

RSpec.shared_examples "an inventory refreshed after bootstrap" do |package = nil|
  let(:bootstrap_executable) { super() }

  before do
    described_class.reset!
  end

  after do
    described_class.reset!
  end

  it "rediscovers installed packages after bootstrapping the manager" do
    allow(described_class).to receive(:package_manager_executable).and_return(nil)
    described_class.installed_packages
    allow(Homebrew::Bundle).to receive(:system)
      .with(HOMEBREW_BREW_FILE, "install", "--formula", described_class.package_manager_name, verbose: false) do
        allow(described_class).to receive(:package_manager_executable)
          .and_return(bootstrap_executable)
        true
      end

    expect(described_class.preinstall!(package)).to be(false)
  end
end

RSpec.shared_examples "a failed inventory dump" do
  extend Test::Helper::TestEach

  let(:inventory_output) { super() }

  def write_inventory(output: "", status: 0)
    super
  end

  let(:brewfile) { mktmpdir/"Brewfile" }

  def dump_inventory(file)
    Homebrew::Bundle::Dumper.dump_brewfile(
      global: false, file:, describe: false, force: true, no_restart: false,
      formulae: false, taps: false, casks: false, extension_types: { described_class.type => true }
    )
  end

  test_each(["", :inventory_output]) do |failed_output|
    context "with #{(failed_output == "") ? "empty" : "partial"} failed output" do
      before do
        described_class.reset!
        write_inventory(output: (failed_output == "") ? "" : inventory_output, status: 2)
      end

      it "preserves an existing Brewfile with force enabled" do
        brewfile.write "# existing Brewfile\n"
        expect { dump_inventory(brewfile.to_s) }.to raise_error(ErrorDuringExecution)
        expect(brewfile.read).to eq("# existing Brewfile\n")
      end

      it "does not create a Brewfile" do
        expect { dump_inventory(brewfile.to_s) }.to raise_error(ErrorDuringExecution)
        expect(brewfile).not_to exist
      end

      it "does not print an inventory fragment to stdout" do
        expect do
          expect { dump_inventory("-") }.to raise_error(ErrorDuringExecution)
        end.not_to output.to_stdout
      end
    end
  end
end

RSpec.shared_examples "a checked package inventory" do |empty_output: "", stderr_forwarded: false|
  include_examples "a checked inventory", :packages, empty_output: empty_output, stderr_forwarded: stderr_forwarded

  context "when dumping" do
    include_examples "a failed inventory dump"
  end
end
