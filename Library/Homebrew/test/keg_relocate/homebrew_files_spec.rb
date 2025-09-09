# frozen_string_literal: true

require "keg_relocate"
require "keg"

RSpec.describe Keg, "#homebrew_created_file?" do
  let(:keg) { instance_double(described_class) }
  let(:path) { Pathname.new("/tmp/test") }

  before do
    allow(keg).to receive(:path).and_return(path)
    allow(keg).to receive(:homebrew_created_file?).and_call_original
  end

  it "identifies Homebrew service files correctly" do
    plist_file = instance_double(Pathname, extname: ".plist", basename: Pathname.new("homebrew.foo.plist"))
    service_file = instance_double(Pathname, extname: ".service", basename: Pathname.new("homebrew.foo.service"))
    timer_file = instance_double(Pathname, extname: ".timer", basename: Pathname.new("homebrew.foo.timer"))
    regular_file = instance_double(Pathname, extname: ".txt", basename: Pathname.new("readme.txt"))
    non_homebrew_plist = instance_double(Pathname, extname: ".plist", basename: Pathname.new("com.example.foo.plist"))

    allow(plist_file.basename).to receive(:to_s).and_return("homebrew.foo.plist")
    allow(service_file.basename).to receive(:to_s).and_return("homebrew.foo.service")
    allow(timer_file.basename).to receive(:to_s).and_return("homebrew.foo.timer")
    allow(regular_file.basename).to receive(:to_s).and_return("readme.txt")
    allow(non_homebrew_plist.basename).to receive(:to_s).and_return("com.example.foo.plist")

    expect(keg.homebrew_created_file?(plist_file)).to be true
    expect(keg.homebrew_created_file?(service_file)).to be true
    expect(keg.homebrew_created_file?(timer_file)).to be true
    expect(keg.homebrew_created_file?(regular_file)).to be false
    expect(keg.homebrew_created_file?(non_homebrew_plist)).to be false
  end
end

RSpec.describe Keg, "#prepare_relocation_to_placeholders_for_homebrew_files" do
  include FileUtils

  let(:keg_path) { Pathname.new(Dir.mktmpdir) }
  let(:keg) { described_class.new(keg_path) }

  after do
    rmtree keg_path
  end

  it "creates relocation with full prefix replacement for Homebrew files" do
    relocation = keg.prepare_relocation_to_placeholders_for_homebrew_files

    # Verify that the relocation includes full prefix replacement
    prefix_old, prefix_new = relocation.replacement_pair_for(:prefix)
    
    expect(prefix_new).to eq("@@HOMEBREW_PREFIX@@")
    expect(prefix_old).to be_a(Regexp)
    expect("#{HOMEBREW_PREFIX}/bin/foo").to match(prefix_old)
  end
end

RSpec.describe Keg, "#replace_text_in_files with Homebrew-created files" do
  include FileUtils

  let(:keg_path) { Pathname.new(Dir.mktmpdir) }
  let(:keg) { described_class.new(keg_path) }

  before do
    allow(keg).to receive(:name).and_return("test-formula")
    allow(keg).to receive(:new_usr_local_relocation?).and_return(true)
  end

  after do
    rmtree keg_path
  end

  it "applies full relocation to Homebrew-created files" do
    # Create a mock service file
    service_file = keg_path/"homebrew.test-formula.service"
    service_content = <<~SERVICE
      [Unit]
      Description=Test Service

      [Service]
      ExecStart=#{HOMEBREW_PREFIX}/bin/test-command
      Environment="PATH=#{HOMEBREW_PREFIX}/bin:#{HOMEBREW_PREFIX}/sbin:/usr/bin"
      WorkingDirectory=#{HOMEBREW_PREFIX}/var/test

      [Install]
      WantedBy=multi-user.target
    SERVICE
    
    service_file.write(service_content)
    
    # Create a regular file that should get selective relocation
    regular_file = keg_path/"test.txt"
    regular_content = <<~CONTENT
      This is a test file.
      It references #{HOMEBREW_PREFIX}/opt/something
      And also #{HOMEBREW_PREFIX}/bin/something
    CONTENT
    
    regular_file.write(regular_content)
    
    # Mock the text_files method to return our test files
    allow(keg).to receive(:text_files).and_return([service_file.basename, regular_file.basename])
    allow(keg).to receive(:libtool_files).and_return([])
    
    # Create a regular relocation that would only replace specific paths
    relocation = keg.prepare_relocation_to_placeholders
    
    # Call replace_text_in_files
    changed_files = keg.replace_text_in_files(relocation)
    
    # Check results
    expect(changed_files).to include(service_file.basename)
    expect(changed_files).to include(regular_file.basename)
    
    # Service file should have full relocation (including /bin path)
    service_result = service_file.read
    expect(service_result).to include("@@HOMEBREW_PREFIX@@/bin/test-command")
    expect(service_result).to include("PATH=@@HOMEBREW_PREFIX@@/bin:@@HOMEBREW_PREFIX@@/sbin:/usr/bin")
    expect(service_result).to include("WorkingDirectory=@@HOMEBREW_PREFIX@@/var/test")
    
    # Regular file should have selective relocation (only /opt path replaced)
    regular_result = regular_file.read
    expect(regular_result).to include("@@HOMEBREW_PREFIX@@/opt/something")
    # bin path should NOT be replaced in regular files when using new usr local relocation
    expect(regular_result).to include("#{HOMEBREW_PREFIX}/bin/something")
  end
end