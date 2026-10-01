# typed: strict
# frozen_string_literal: true

require "mktemp"

RSpec.describe Mktemp do
  it "names compact temporary directories" do
    described_class.new("sandbox", compact: true, parent: mktmpdir).run(chdir: false) do |staging|
      directory = staging.tmpdir
      raise "Temporary directory is unexpectedly unset." if directory.nil?

      expect(directory.basename.to_s).to match(/\As-[A-Za-z0-9]{8}\z/)
    end
  end

  it "creates compact temporary directories with mode 0700" do
    described_class.new("sandbox", compact: true, parent: mktmpdir).run(chdir: false) do |staging|
      directory = staging.tmpdir
      raise "Temporary directory is unexpectedly unset." if directory.nil?

      expect(directory.stat.mode & 0777).to eq(0700)
    end
  end
end
