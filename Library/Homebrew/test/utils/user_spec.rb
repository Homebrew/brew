# frozen_string_literal: true

require "utils/user"

describe User do
  subject { described_class.current }

  it { is_expected.to eq ENV.fetch("USER") }

  describe "#gui?" do
    before do
      allow(SystemCommand).to receive(:run)
        .with("who", any_args)
        .and_return([who_output, "", instance_double(Process::Status, success?: true)])
    end

    context "when the current user is in a console session" do
      let(:who_output) do
        <<~EOS
          #{ENV.fetch("USER")}   console  Oct  1 11:23
          #{ENV.fetch("USER")}   ttys001  Oct  1 11:25
        EOS
      end

      its(:gui?) { is_expected.to be true }
    end

    context "when the current user is not in a console session" do
      let(:who_output) do
        <<~EOS
          #{ENV.fetch("USER")}   ttys001  Oct  1 11:25
          fake_user              ttys002  Oct  1 11:27
        EOS
      end

      its(:gui?) { is_expected.to be false }
    end
  end
end
