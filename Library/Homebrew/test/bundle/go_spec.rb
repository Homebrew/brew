# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/shared_examples/inventory"
require "bundle/extensions/go"

RSpec.describe Homebrew::Bundle::Go do
  let(:inventory_bin) do
    bin = mktmpdir
    binary = bin/"example; literal $(value)"
    binary.write ""
    binary.chmod 0755
    bin
  end
  let(:inventory_output) { "\tpath\texample.com/tool\n" }
  let(:inventory_records) { ["example.com/tool"] }

  describe "checked inventory" do
    before do
      allow(described_class).to receive(:command_output)
        .with(anything, args: ["env", anything], print_stderr: true).and_return(inventory_bin.to_s)
    end

    it_behaves_like "a checked package inventory"
    it_behaves_like "a checked inventory", :installed_packages
  end

  describe "checked discovery" do
    let(:go) { mktmpdir/"go" }
    let(:bin) { mktmpdir }

    before do
      described_class.reset!
      (bin/"first").write ""
      (bin/"first").chmod 0755
      (bin/"second").write ""
      (bin/"second").chmod 0755
      go.write <<~SH
        #!/bin/sh
        if [ "$1" = env ]; then
          printf '%s\\n' '#{bin}'
          exit 0
        fi
        if [ "$3" = '#{bin}/first' ]; then
          printf '\\tpath\\texample.com/tool\\n'
          exit 0
        fi
        printf '%s\\n' 'metadata unavailable' >&2
        exit 1
      SH
      go.chmod 0755
      allow(described_class).to receive(:package_manager_executable).and_return(go)
    end

    after do
      described_class.reset!
    end

    def write_metadata(output)
      go.write <<~SH
        #!/bin/sh
        if [ "$1" = env ]; then printf '%s' '#{bin}'; exit 0; fi
        printf '%s' #{output.shellescape}
      SH
    end

    test_each(["GOBIN", "GOPATH"]) do |variable|
      it "rejects a failed #{variable} query" do
        go.write <<~SH
          #!/bin/sh
          if [ "$2" = '#{variable}' ]; then exit 2; fi
          printf '%s' '#{bin}'
        SH
        expect { described_class.packages }.to raise_error(ErrorDuringExecution)
      end
    end

    it "reports an unreadable directory" do
      allow(Dir).to receive(:children).with(bin.to_s).and_raise(Errno::EACCES)
      expect { described_class.packages }.to raise_error(Errno::EACCES)
    end

    test_each(["GOBIN", "GOPATH"]) do |variable|
      context "when the binary directory comes from #{variable}" do
        let(:bin_dir) { mktmpdir/"bin" }

        before do
          allow(described_class).to receive(:command_output)
            .with(go, args: ["env", "GOBIN"], print_stderr: true)
            .and_return((variable == "GOBIN") ? bin_dir.to_s : "")
          allow(described_class).to receive(:command_output)
            .with(go, args: ["env", "GOPATH"], print_stderr: true).and_return(bin_dir.dirname.to_s)
        end

        it "returns an empty inventory when the directory does not exist" do
          expect(described_class.packages).to eq([])
        end

        it "preserves an existing Brewfile when the directory is a regular file" do
          bin_dir.write ""
          brewfile = mktmpdir/"Brewfile"
          brewfile.write "# existing Brewfile\n"

          expect do
            Homebrew::Bundle::Dumper.dump_brewfile(
              global: false, file: brewfile.to_s, describe: false, force: true, no_restart: false,
              formulae: false, taps: false, casks: false, extension_types: { go: true }
            )
          end.to raise_error(Errno::ENOTDIR)
          expect(brewfile.read).to eq("# existing Brewfile\n")
        end
      end
    end

    test_each(["not a Go executable", "unrecognized file format"]) do |diagnostic|
      it "excludes only an exact file-bound #{diagnostic} negative" do
        go.write <<~SH
          #!/bin/sh
          if [ "$1" = env ]; then printf '%s' '#{bin}'; exit 0; fi
          printf '%s: could not read Go build info from %s: %s\\n' "$3" "$3" '#{diagnostic}' >&2
          exit 1
        SH
        expect(described_class.packages).to eq([])
      end
    end

    it "rejects metadata even with a recognised non-Go diagnostic" do
      go.write <<~SH
        #!/bin/sh
        if [ "$1" = env ]; then printf '%s' '#{bin}'; exit 0; fi
        printf '\\tpath\\texample.com/tool\\n'
        printf '%s: could not read Go build info from %s: not a Go executable\\n' "$3" "$3" >&2
        exit 1
      SH
      expect { described_class.packages }.to raise_error(ErrorDuringExecution)
    end

    test_each_hash({
      "\tpath\texample.com/tool\n"             => ["example.com/tool"],
      "\tpath\texample.com/Tools/cmd/c++/v2\n" => ["example.com/Tools/cmd/c++/v2"],
      "\tpath\tcommand-line-arguments\n"       => [],
      ""                                       => [],
      "\tmod\texample.com/tool\n"              => [],
    }) do |output, packages|
      it "reads package paths from #{output.inspect}" do
        write_metadata(output)
        expect(described_class.packages).to eq(packages)
      end
    end

    test_each(["", " ", " example.com/tool ", "example.com/my tool", "\textra",
               "example.com/tool\textra", "example.com/to\rol", "example.com/to\vol", "example.com/to\fol"]) do |path|
      it "rejects a malformed path #{path.inspect} without selecting a later record" do
        write_metadata("\tpath\t#{path}\n\tpath\texample.com/other\n")
        expect { described_class.packages }
          .to raise_error(RuntimeError, "Invalid Go package path for #{(bin/"first").to_s.inspect}: #{path.inspect}")
      end
    end

    test_each([:packages, :installed_packages]) do |inventory_method|
      it "retries #{inventory_method} after malformed metadata is corrected" do
        write_metadata("\tpath\texample.com/my tool\n")
        expect do
          described_class.public_send(inventory_method)
        end.to raise_error(RuntimeError, /Invalid Go package path/)
        write_metadata("\tpath\texample.com/tool\n")

        expect(described_class.public_send(inventory_method)).to eq(["example.com/tool"])
      end
    end

    it "preserves an existing Brewfile when successful metadata is malformed" do
      brewfile = mktmpdir/"Brewfile"
      brewfile.write "# existing Brewfile\n"
      write_metadata("\tpath\texample.com/my tool\n")

      expect do
        Homebrew::Bundle::Dumper.dump_brewfile(
          global: false, file: brewfile.to_s, describe: false, force: true, no_restart: false,
          formulae: false, taps: false, casks: false, extension_types: { go: true }
        )
      end.to raise_error(RuntimeError, /Invalid Go package path/)
      expect(brewfile.read).to eq("# existing Brewfile\n")
    end

    it "rejects later malformed metadata before removing any executable" do
      go.write <<~SH
        #!/bin/sh
        if [ "$1" = env ]; then printf '%s' '#{bin}'; exit 0; fi
        if [ "$3" = '#{bin}/first' ]; then
          printf '\\tpath\\texample.com/tool\\n'
        else
          printf '\\tpath\\texample.com/my tool\\n'
        fi
      SH
      expect(File).not_to receive(:unlink)
      expect { described_class.cleanup!(["example.com/tool"]) }
        .to raise_error(RuntimeError, /Invalid Go package path.*second/)
    end

    it "rejects an unknown metadata failure after accepted metadata" do
      expect { described_class.packages }.to raise_error(ErrorDuringExecution, /metadata unavailable/)
    end

    it "finishes discovery before removing any executable" do
      expect(File).not_to receive(:unlink)
      expect { described_class.cleanup!(["example.com/tool"]) }.to raise_error(ErrorDuringExecution)
    end
  end

  describe "dumping" do
    subject(:dumper) { described_class }

    context "when go is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      specify do
        expect(dumper.packages).to be_empty
        expect(dumper.dump).to eql("")
      end
    end

    context "when go is installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("go"))
      end

      it "returns package list" do
        allow(described_class).to receive(:`).and_raise("Shell execution is not permitted")
        allow(described_class).to receive(:command_output)
          .with(Pathname("go"), args:         ["env", "GOBIN"],
                                print_stderr: true).and_return("")
        allow(described_class).to receive(:command_output)
          .with(Pathname("go"), args:         ["env", "GOPATH"],
                                print_stderr: true).and_return("/Users/test/go")
        allow(Dir).to receive(:children).with("/Users/test/go/bin").and_return(["crush"])
        allow(File).to receive(:executable?).with("/Users/test/go/bin/crush").and_return(true)
        allow(File).to receive(:directory?).with("/Users/test/go/bin/crush").and_return(false)
        allow(SystemCommand).to receive(:run)
          .with(Pathname("go"), args: ["version", "-m", "/Users/test/go/bin/crush"], print_stderr: false)
          .and_return(instance_double(SystemCommand::Result,
                                      exit_status:     0,
                                      assert_success!: nil,
                                      stdout:          "\tpath\tgithub.com/charmbracelet/crush\n"))
        expect(dumper.packages).to eql(["github.com/charmbracelet/crush"])
      end

      it "dumps package list" do
        allow(dumper).to receive(:packages).and_return(["github.com/charmbracelet/crush"])
        expect(dumper.dump).to eql('go "github.com/charmbracelet/crush"')
      end
    end
  end

  describe "bootstrap cache invalidation" do
    let(:bootstrap_executable) { Pathname("go") }

    before do
      allow(described_class).to receive(:discovered_binaries).and_return({ "/tmp/tool" => "example.com/tool" })
    end

    it_behaves_like "an inventory refreshed after bootstrap", "example.com/tool"
  end

  describe "installing" do
    context "when Go is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      it "tries to install go" do
        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "go", verbose: false)
                          .and_return(true)
        expect { described_class.preinstall!("github.com/charmbracelet/crush") }.to raise_error(RuntimeError)
      end

      it "preserves upgrade_formulae while bootstrapping Go" do
        Homebrew::Bundle.upgrade_formulae = "foo,bar"

        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "go", verbose: false)
                          .and_return(true)
        expect { described_class.preinstall!("github.com/charmbracelet/crush") }.to raise_error(RuntimeError)
        expect(Homebrew::Bundle.upgrade_formulae).to eql(["foo", "bar"])
      end
    end

    context "when Go is installed" do
      before do
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("go"))
      end

      context "when package is installed" do
        before do
          allow(described_class).to receive(:installed_packages)
            .and_return(["github.com/charmbracelet/crush"])
        end

        it "skips" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("github.com/charmbracelet/crush")).to be(false)
        end
      end

      context "when package is not installed" do
        before do
          allow(described_class).to receive_messages(packages: [], installed_packages: [])
        end

        it "installs package" do
          expect(Homebrew::Bundle).to \
            receive(:system).with("go", "install", "github.com/charmbracelet/crush@latest", verbose: false)
                            .and_return(true)
          expect(described_class.preinstall!("github.com/charmbracelet/crush")).to be(true)
          expect(described_class.install!("github.com/charmbracelet/crush")).to be(true)
        end

        it "updates dump output after install in the same process" do
          expect(Homebrew::Bundle).to \
            receive(:system).with("go", "install", "github.com/charmbracelet/crush@latest", verbose: false)
                            .and_return(true)

          described_class.install!("github.com/charmbracelet/crush")

          expect(described_class.dump).to eql('go "github.com/charmbracelet/crush"')
        end
      end
    end
  end

  describe "cleanup" do
    before do
      described_class.reset!
      pkgs = %w[github.com/charmbracelet/crush github.com/golangci/golangci-lint/v2/cmd/golangci-lint]
      allow(described_class).to receive_messages(
        package_manager_executable: Pathname.new("go"),
        packages:                   pkgs,
        installed_packages:         pkgs,
      )
    end

    it "returns packages not in Brewfile entries" do
      entries = [Homebrew::Bundle::Dsl::Entry.new(:go, "github.com/charmbracelet/crush")]
      expect(described_class.cleanup_items(entries))
        .to eql(%w[github.com/golangci/golangci-lint/v2/cmd/golangci-lint])
    end

    it "reports a missing executable when removals are queued" do
      Homebrew.failed = false
      allow(described_class).to receive(:package_manager_executable).and_return(nil)

      expect do
        described_class.cleanup!(["example.com/tools/example"])
      end.to(
        change(Homebrew, :failed?).from(false).to(true)
          .and(output(/Failed to remove Go executables: go executable not found/).to_stderr),
      )
    end

    it "does not report a missing executable when no removals are queued" do
      allow(described_class).to receive(:package_manager_executable).and_return(nil)

      expect do
        described_class.cleanup!([])
      end.to(output("").to_stderr.and(output("").to_stdout))
    end

    it "removes binaries by their literal names" do
      binary = "/Users/test/go/bin/cr;ush $(touch pwned)"
      allow(described_class).to receive(:`).and_raise("Shell execution is not permitted")
      allow(described_class).to receive(:puts)
      allow(described_class).to receive(:command_output).with(Pathname("go"), args:         ["env", "GOBIN"],
                                                                              print_stderr: true).and_return("")
      allow(described_class).to receive(:command_output).with(Pathname("go"), args:         ["env", "GOPATH"],
                                                                              print_stderr: true)
                                                        .and_return("/Users/test/go")
      allow(Dir).to receive(:children).with("/Users/test/go/bin").and_return([File.basename(binary)])
      allow(File).to receive(:executable?).with(binary).and_return(true)
      allow(File).to receive(:directory?).with(binary).and_return(false)
      allow(SystemCommand).to receive(:run)
        .with(Pathname("go"), args: ["version", "-m", binary], print_stderr: false)
        .and_return(instance_double(SystemCommand::Result,
                                    exit_status:     0,
                                    assert_success!: nil,
                                    stdout:          "\tpath\tgithub.com/charmbracelet/crush\n"))

      expect(File).to receive(:unlink).with(binary)

      described_class.cleanup!(["github.com/charmbracelet/crush"])
    end

    context "with selected executables" do
      let(:bin_dir) { mktmpdir }
      let(:executables) { %w[first second].map { |name| (bin_dir/name).to_s } }

      # Use real files rather than stubbing `File.unlink`, which `Tempfile` finalizers also call.
      before do
        Homebrew.failed = false
        allow(described_class).to receive(:command_output)
          .with(Pathname("go"), args: ["env", "GOBIN"], print_stderr: true).and_return(bin_dir.to_s)
        allow(described_class).to receive(:command_output)
          .with(Pathname("go"), args: ["env", "GOPATH"], print_stderr: true).and_return("/tmp/go")
        executables.each do |executable|
          FileUtils.touch executable
          FileUtils.chmod "+x", executable
          allow(SystemCommand).to receive(:run)
            .with(Pathname("go"), args: ["version", "-m", executable], print_stderr: false)
            .and_return(instance_double(SystemCommand::Result,
                                        exit_status:     0,
                                        assert_success!: nil,
                                        stdout:          "\tpath\texample.com/tools/example\n"))
        end
      end

      it "counts removed executables rather than packages" do
        expect do
          described_class.cleanup!(["example.com/tools/example"])
        end.to output("Removed 2 Go executables\n").to_stdout.and output("").to_stderr
      end

      it "does not mark successful cleanup as failed" do
        allow(described_class).to receive(:puts)

        expect do
          described_class.cleanup!(["example.com/tools/example"])
        end.not_to change(Homebrew, :failed?)
      end

      it "reports deletion errors and continues with the next executable" do
        allow(File).to receive(:unlink).and_call_original
        expect(File).to receive(:unlink).with(executables.first).ordered.and_raise(Errno::EACCES)
        expect(File).to receive(:unlink).with(executables.last).ordered.and_return(1)

        expect do
          described_class.cleanup!(["example.com/tools/example"])
        end.to(
          change(Homebrew, :failed?).from(false).to(true)
            .and(output("Removed 1 Go executable\n").to_stdout)
            .and(output(
              a_string_including("Failed to remove Go executable #{executables.first}"),
            ).to_stderr),
        )
      end

      it "does not count an already absent executable as removed" do
        allow(SystemCommand).to receive(:run)
          .with(Pathname("go"), args: ["version", "-m", executables.first], print_stderr: false) do
          FileUtils.rm executables.first
          instance_double(SystemCommand::Result,
                          exit_status:     0,
                          assert_success!: nil,
                          stdout:          "\tpath\texample.com/tools/example\n")
        end

        expect do
          described_class.cleanup!(["example.com/tools/example"])
        end.to output("Removed 1 Go executable\n").to_stdout
                                                  .and output("").to_stderr
      end
    end

    it "returns frozen empty array when go is not installed" do
      allow(described_class).to receive(:package_manager_installed?).and_return(false)
      entries = [Homebrew::Bundle::Dsl::Entry.new(:go, "github.com/charmbracelet/crush")]
      expect(described_class.cleanup_items(entries)).to eql([])
    end
  end
end
