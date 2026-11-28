# typed: true
# frozen_string_literal: true

require "system_config"

RSpec.describe SystemConfig do
  describe "::dump_verbose_config" do
    it "prints N/A for formulae when the API data cannot be downloaded" do
      allow(described_class).to receive(:config_sections).and_return([:linux_config])
      allow(Formulary).to receive(:factory).and_raise(ErrorDuringExecution.new(["curl"], status: 7))
      out = StringIO.new

      described_class.dump_verbose_config(out)

      expect(out.string).to include("glibc: N/A")
    end
  end
end
