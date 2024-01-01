# frozen_string_literal: true

require "messages"
require "spec_helper"

describe Messages do
  let(:messages) { described_class.new }
  let(:test_formula) { formula("foo") { url("https://brew.sh/foo-0.1.tgz") } }
  let(:elapsed_time) { 1.1 }

  describe "#record_caveats" do
    it "adds a caveat" do
      expect do
        messages.record_caveats(test_formula, "Zsh completions were installed")
      end.to change(messages.caveats, :count).by(1)
    end
  end

  describe "#package_installed" do
    it "increases the package count" do
      expect do
        messages.package_installed(test_formula, elapsed_time)
      end.to change(messages, :package_count).by(1)
    end

    it "adds to install_times" do
      expect do
        messages.package_installed(test_formula, elapsed_time)
      end.to change(messages.install_times, :count).by(1)
    end
  end

  describe "#display_messages" do
    context "when package_count is less than two" do
      before do
        messages.record_caveats(test_formula, "Zsh completions were installed")
        messages.package_installed(test_formula, elapsed_time)
      end

      it "doesn't print caveat details" do
        expect { messages.display_messages }.not_to output.to_stdout
      end
    end

    context "when caveats is empty" do
      before do
        messages.package_installed(test_formula, elapsed_time)
      end

      it "doesn't print caveat details" do
        expect { messages.display_messages }.not_to output.to_stdout
      end
    end

    context "when package_count is greater than one and caveats are present" do
      let(:test_formula2) { formula("bar") { url("https://brew.sh/bar-0.1.tgz") } }

      before do
        messages.record_caveats(test_formula, "Zsh completions were installed")
        messages.package_installed(test_formula, elapsed_time)
        messages.package_installed(test_formula2, elapsed_time)
      end

      it "prints caveat details" do
        expect { messages.display_messages }.to output(
          <<~EOS,
            ==> Caveats
            ==> foo
            Zsh completions were installed
          EOS
        ).to_stdout
      end
    end

    context "when the `display_times` argument is true" do
      context "when `install_times` is empty" do
        it "doesn't print anything" do
          expect { messages.display_messages(display_times: true) }.not_to output.to_stdout
        end
      end

      context "when `install_times` is present" do
        before do
          messages.package_installed(test_formula, elapsed_time)
        end

        it "prints installation times" do
          expect { messages.display_messages(display_times: true) }.to output(
            <<~EOS,
              ==> Installation times
              foo                       1.100 s
            EOS
          ).to_stdout
        end
      end
    end

    context "when the `display_times` argument isn't specified" do
      it "doesn't print installation times" do
        expect { messages.display_messages }.not_to output.to_stdout
      end
    end
  end
end
