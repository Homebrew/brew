# frozen_string_literal: true

require "system_command"

RSpec.describe SystemCommand::Result do
  RSpec::Matchers.alias_matcher :a_string_containing, :include

  subject(:result) do
    described_class.new([], output_array, instance_double(Process::Status, exitstatus: 0, success?: true),
                        secrets: [])
  end

  let(:output_array) do
    [
      [:stdout, "output\n"],
      [:stderr, "error\n"],
    ]
  end

  describe "#to_ary" do
    it "can be destructed like `Open3.capture3`" do
      out, err, status = result

      expect(out).to eq "output\n"
      expect(err).to eq "error\n"
      expect(status).to be_a_success
    end
  end

  describe "#stdout" do
    it "returns the standard output" do
      expect(result.stdout).to eq "output\n"
    end
  end

  describe "#stderr" do
    it "returns the standard error output" do
      expect(result.stderr).to eq "error\n"
    end
  end

  describe "#merged_output" do
    it "returns the combined standard and standard error output" do
      expect(result.merged_output).to eq "output\nerror\n"
    end
  end

  describe "#plist" do
    subject(:result_plist) { result.plist }

    let(:output_array) { [[:stdout, stdout]] }
    let(:garbage) do
      <<~EOS
        Hello there! I am in no way XML am I?!?!

          That's a little silly... you were expecting XML here!

        What is a parser to do?

        Hopefully <not> explode!
      EOS
    end
    let(:plist) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>system-entities</key>
          <array>
            <dict>
              <key>content-hint</key>
              <string>Apple_partition_map</string>
              <key>dev-entry</key>
              <string>/dev/disk3s1</string>
              <key>potentially-mountable</key>
              <false/>
              <key>unmapped-content-hint</key>
              <string>Apple_partition_map</string>
            </dict>
            <dict>
              <key>content-hint</key>
              <string>Apple_partition_scheme</string>
              <key>dev-entry</key>
              <string>/dev/disk3</string>
              <key>potentially-mountable</key>
              <false/>
              <key>unmapped-content-hint</key>
              <string>Apple_partition_scheme</string>
            </dict>
            <dict>
              <key>content-hint</key>
              <string>Apple_HFS</string>
              <key>dev-entry</key>
              <string>/dev/disk3s2</string>
              <key>mount-point</key>
              <string>/private/tmp/dmg.BhfS2g</string>
              <key>potentially-mountable</key>
              <true/>
              <key>unmapped-content-hint</key>
              <string>Apple_HFS</string>
              <key>volume-kind</key>
              <string>hfs</string>
            </dict>
          </array>
        </dict>
        </plist>
      XML
    end

    context "when stdout contains garbage before XML" do
      let(:stdout) do
        <<~EOS
          #{garbage}
          #{plist}
        EOS
      end

      it "ignores garbage" do
        expect(result_plist["system-entities"].length).to eq(3)
      end

      context "when verbose" do
        before do
          allow(Context).to receive(:current).and_return(Context::ContextStruct.new(verbose: true))
        end

        it "warns about garbage" do
          expect { result_plist }
            .to output(a_string_containing(garbage)).to_stderr
        end
      end
    end

    context "when stdout contains garbage after XML" do
      let(:stdout) do
        <<~EOS
          #{plist}
          #{garbage}
        EOS
      end

      it "ignores garbage" do
        expect(result_plist["system-entities"].length).to eq(3)
      end

      context "when verbose" do
        before do
          allow(Context).to receive(:current).and_return(Context::ContextStruct.new(verbose: true))
        end

        it "warns about garbage" do
          expect { result_plist }
            .to output(a_string_containing(garbage)).to_stderr
        end
      end
    end

    context "when there's a hdiutil stdout" do
      let(:stdout) { plist }

      it "successfully parses it" do
        expect(result_plist.keys).to eq(["system-entities"])
        expect(result_plist["system-entities"].length).to eq(3)
        expect(result_plist["system-entities"].map { |e| e["dev-entry"] })
          .to eq(["/dev/disk3s1", "/dev/disk3", "/dev/disk3s2"])
      end
    end

    context "when the stdout of the command is empty" do
      let(:stdout) { "" }

      it "returns nil" do
        expect(result_plist).to be_nil
      end
    end
  end
end
