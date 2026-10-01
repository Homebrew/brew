# typed: strict
# frozen_string_literal: true

require "formula_assertions"

RSpec.describe Homebrew::Assertions do
  sig { returns(Homebrew::Assertions) }
  subject(:formula_assertions) do
    Class.new do
      include Homebrew::Assertions
    end.new
  end

  it "preserves the shell exit status for a non-executable Pathname" do
    executable = mktmpdir/"not-executable"
    executable.write("")

    expect(formula_assertions.shell_output(executable, 126)).to eq("")
  end

  it "preserves shell syntax for String commands" do
    expect(formula_assertions.shell_output("printf shell | /bin/cat")).to eq("shell")
  end

  it "passes Pathname metacharacters literally" do
    executable = mktmpdir/"directory;$(false)"/"executable"
    executable.dirname.mkpath
    executable.write("#!/bin/sh\nprintf literal\n")
    executable.chmod(0755)

    expect(formula_assertions.shell_output(executable)).to eq("literal")
  end

  it "executes a relative Pathname literally rather than through PATH" do
    directory = mktmpdir
    (directory/"tool").write("#!/bin/sh\nprintf local\n")
    (directory/"tool").chmod(0755)
    shadow = directory/"shadow"
    shadow.mkpath
    (shadow/"tool").write("#!/bin/sh\nprintf shadowed\n")
    (shadow/"tool").chmod(0755)
    ENV["PATH"] = "#{shadow}:/usr/bin:/bin"

    expect(directory.cd { formula_assertions.shell_output(Pathname("tool")) }).to eq("local")
  end
end
