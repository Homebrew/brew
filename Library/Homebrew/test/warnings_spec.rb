# typed: strict
# frozen_string_literal: true

require "warnings"

RSpec.describe Warnings do
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
