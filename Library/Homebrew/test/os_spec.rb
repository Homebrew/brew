# typed: strict
# frozen_string_literal: true

require "os"

RSpec.describe OS::ThirdPartyHomebrew do
  before { allow(Process).to receive(:ppid).and_return(1) }

  it "detects a platform-specific marker only on the matching platform" do
    mktmpdir do |dir|
      marker = dir/"wrapper"
      marker.write("")
      wrapper = described_class.new(issues_url: "https://example.com/issues", files: { macos: marker.to_s })
      stub_const("OS::ThirdPartyHomebrew::CONFIGURATIONS", { wrapper: })

      expect([described_class.detect(macos: true), described_class.detect(macos: false)]).to eq([wrapper, nil])
    end
  end

  it "detects a management tool by the owner of this repository" do
    require "etc"
    allow(Etc).to receive(:getpwuid).with(HOMEBREW_REPOSITORY.stat.uid)
                                    .and_return(instance_double(Etc::Passwd, name: "example-manager"))
    inventory = described_class.new(repository_owner: "other-manager", presence_file: __FILE__)
    manager = described_class.new(repository_owner: "example-manager")
    stub_const("OS::ThirdPartyHomebrew::CONFIGURATIONS", { inventory:, manager: })

    expect(described_class.detect(macos: true)).to eq(manager)
  end

  it "keeps an unresolvable repository owner from identifying a managed installation" do
    require "etc"
    allow(Etc).to receive(:getpwuid).with(HOMEBREW_REPOSITORY.stat.uid).and_raise(ArgumentError)
    manager = described_class.new(repository_owner: "example-manager", presence_file: __FILE__)
    stub_const("OS::ThirdPartyHomebrew::CONFIGURATIONS", { manager: })

    expect(described_class.detect(macos: false)).to be_nil
  end

  it "recognises a provisioner running through an interpreter in an ancestor process" do
    provisioner = described_class.new(command: /\Aexample-provisioner\z/)
    stub_const("OS::ThirdPartyHomebrew::CONFIGURATIONS", { provisioner: })
    allow(Process).to receive(:ppid).and_return(123)
    allow(Utils).to receive(:popen_read_text).with("/bin/ps", "-ww", "-p", "123", "-o", "ppid=,args=", err: :close)
                                             .and_return("  456 /bin/sh -c brew install foo")
    allow(Utils).to receive(:popen_read_text).with("/bin/ps", "-ww", "-p", "456", "-o", "ppid=,args=", err: :close)
                                             .and_return("    1 /usr/bin/ruby /opt/bin/example-provisioner apply")

    expect(described_class.detect(macos: false)).to eq(provisioner)
  end

  it "recognises the provisioner's script after Python options" do
    provisioner = described_class.new(command: /\Aexample-provisioner\.py\z/, issues_url: "https://example.com/issues")
    stub_const("OS::ThirdPartyHomebrew::CONFIGURATIONS", { provisioner: })
    allow(Process).to receive(:ppid).and_return(123)
    allow(Utils).to receive(:popen_read_text)
      .and_return("    1 /usr/bin/python3.12 -u /tmp/example-provisioner.py")

    expect(described_class.detect(macos: false)).to eq(provisioner)
  end

  it "consumes interpreter option values and stops at the script" do
    expect(described_class.command_name("python3.12", "-I -W ignore -Xdev -- /bin/tool.py other.py")).to eq("tool.py")
  end

  it "ignores inline code, module names, standard input and arguments to other scripts" do
    expect([
      described_class.command_name("python3", "-u -c example-provisioner"),
      described_class.command_name("python3", "-um example-provisioner"),
      described_class.command_name("python3", "-u - example-provisioner"),
      described_class.command_name("ruby", "-w -e example-provisioner"),
      described_class.command_name("python3", "-u ordinary.py example-provisioner"),
    ]).to eq([nil, nil, nil, nil, "ordinary.py"])
  end

  it "ignores provisioner names used as ordinary command arguments" do
    provisioner = described_class.new(command: /\Aexample-provisioner\z/)
    stub_const("OS::ThirdPartyHomebrew::CONFIGURATIONS", { provisioner: })
    allow(Process).to receive(:ppid).and_return(123)
    allow(Utils).to receive(:popen_read_text).and_return("    1 /usr/bin/git show example-provisioner")

    expect(described_class.detect(macos: false)).to be_nil
  end

  it "matches only the managed prefix on the configured platform" do
    managed = described_class.new(prefixes: { macos: "/managed/brew" })
    stub_const("OS::ThirdPartyHomebrew::CONFIGURATIONS", { managed: })

    stub_const("HOMEBREW_PREFIX", Pathname("/other/brew"))
    other_prefix = described_class.detect(macos: true)
    stub_const("HOMEBREW_PREFIX", Pathname("/managed/brew"))

    expect([other_prefix, described_class.detect(macos: false), described_class.detect(macos: true)])
      .to eq([nil, nil, managed])
  end
end
