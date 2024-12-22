# frozen_string_literal: true

require "hardware"

RSpec.describe Hardware::CPU do
  describe "::type" do
    let(:cpu_types) do
      [
        :arm,
        :intel,
        :ppc,
        :dunno,
      ]
    end

    it "returns the current CPU's type as a symbol, or :dunno if it cannot be detected" do
      expect(cpu_types).to include(described_class.type)
    end
  end

  describe "::family" do
    let(:cpu_families) do
      [
        :alderlake,
        :amd_k7,
        :amd_k8,
        :amd_k8_k10_hybrid,
        :amd_k10,
        :amd_k12,
        :arm,
        :arm_blizzard_avalanche,
        :arm_brava,
        :arm_donan,
        :arm_firestorm_icestorm,
        :arm_hurricane_zephyr,
        :arm_ibiza,
        :arm_lightning_thunder,
        :arm_lobos,
        :arm_monsoon_mistral,
        :arm_palma,
        :arm_twister,
        :arm_typhoon,
        :arm_vortex_tempest,
        :arrowlake,
        :atom,
        :bobcat,
        :broadwell,
        :bulldozer,
        :cannonlake,
        :cometlake,
        :core,
        :core2,
        :dothan,
        :graniterapids,
        :haswell,
        :icelake,
        :ivybridge,
        :jaguar,
        :kabylake,
        :merom,
        :nehalem,
        :pantherlake,
        :penryn,
        :ppc,
        :prescott,
        :presler,
        :rocketlake,
        :sandybridge,
        :sapphirerapids,
        :skylake,
        :tigerlake,
        :westmere,
        :zen,
        :zen2,
        :zen3,
        :zen4,
        :zen5,
        :dunno,
      ]
    end

    it "returns the current CPU's family name as a symbol, or :dunno if it cannot be detected" do
      expect(cpu_families).to include described_class.family
    end

    context "when hw.cpufamily is 0x573b5eec on a Mac", :needs_macos do
      before do
        allow(described_class)
          .to receive(:sysctl_int)
          .with("hw.cpufamily")
          .and_return(0x573b5eec)
      end

      it "returns :arm_firestorm_icestorm on ARM" do
        allow(described_class).to receive_messages(arm?: true, intel?: false)

        expect(described_class.family).to eq(:arm_firestorm_icestorm)
      end

      it "returns :westmere on Intel" do
        allow(described_class).to receive_messages(arm?: false, intel?: true)

        expect(described_class.family).to eq(:westmere)
      end
    end
  end
end
