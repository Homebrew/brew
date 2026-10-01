# typed: strict
# frozen_string_literal: true

require "warnings"

RSpec.describe Warnings do
  it "raises configured fatal warnings" do
    expect do
      described_class.fail_on(/fatal warning/) { Warning.warn("fatal warning\n") }
    end.to raise_error(RuntimeError, /fatal warning/)
  end

  it "allows explicitly ignored fatal warnings" do
    expect do
      described_class.fail_on(/explicitly ignored fatal warning/) do
        described_class.ignore(/explicitly ignored fatal warning/) do
          Warning.warn("explicitly ignored fatal warning\n")
        end
      end
    end.not_to output.to_stderr
  end

  it "restores fatal warnings after an exception" do
    expect do
      described_class.fail_on(/scoped fatal warning/) { raise "failure" }
    rescue RuntimeError
      Warning.warn("scoped fatal warning\n")
    end.to output("scoped fatal warning\n").to_stderr
  end

  it "restores ignored warnings after an exception" do
    expect do
      described_class.ignore(/ignored warning/) { raise "failure" }
    rescue RuntimeError
      Warning.warn("ignored warning\n")
    end.to output("ignored warning\n").to_stderr
  end

  it "supports nested ignored warnings" do
    expect do
      described_class.ignore(/outer warning/) do
        Warning.warn("outer warning\n")
        described_class.ignore(/inner warning/) do
          Warning.warn("outer warning\n")
          Warning.warn("inner warning\n")
        end
        Warning.warn("outer warning\n")
        Warning.warn("inner warning\n")
      end
      Warning.warn("outer warning\n")
    end.to output("inner warning\nouter warning\n").to_stderr
  end
end
