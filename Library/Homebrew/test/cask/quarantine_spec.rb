# typed: true
# frozen_string_literal: true

require "open3"

RSpec.describe Cask::Quarantine do
  let(:klass) { described_class }

  context "when quarantine support is unavailable" do
    let(:file) { mktmpdir/"Test.app" }

    before do
      allow(klass).to receive_messages(available?: false, xattr: nil)
    end

    it "does not detect quarantine" do
      expect(klass.detect(file)).to be(false)
    end

    it "returns an empty quarantine status" do
      expect(klass.status(file)).to eq("")
    end

    it "does not release quarantine" do
      expect(klass).not_to receive(:system_command)

      klass.release!(download_path: file)
    end

    it "does not propagate quarantine" do
      expect(klass).not_to receive(:system_command!)

      klass.propagate(from: file, to: file)
    end

    it "does not inherit user approval" do
      expect(klass).not_to receive(:system_command)

      klass.inherit_user_approval!(download_path: file)
    end

    it "does not quarantine a cask" do
      expect(klass).not_to receive(:detect)

      klass.cask!(cask: instance_double(Cask::Cask), download_path: file)
    end

    it "does not copy extended attributes" do
      expect(file).not_to receive(:writable?)

      klass.copy_xattrs(file, file, command: class_double(SystemCommand))
    end
  end

  describe ".available?", :needs_macos do
    before do
      klass.remove_instance_variable(:@quarantine_support) if klass.instance_variable_defined?(:@quarantine_support)
    end

    it "uses FFI quarantine support when xattr works" do
      allow(klass).to receive(:xattr).and_return(Pathname("/usr/bin/xattr"))
      allow(klass).to receive(:system_command)
        .with(Pathname("/usr/bin/xattr"), args: ["-h"], print_stderr: false)
        .and_return(instance_double(SystemCommand::Result, success?: true))

      with_env(HOMEBREW_DEVELOPER: nil) do
        expect(klass.available?).to be(true)
      end
    end
  end

  describe ".cask!", :needs_macos do
    let(:cask) do
      instance_double(
        Cask::Cask,
        url:      "https://example.com/download",
        homepage: "https://example.com",
      )
    end

    it "sets the quarantine attribute on a file in a temporary directory" do
      mktmpdir do |tmpdir|
        download_path = tmpdir/"Test.dmg"
        download_path.write("test")

        expect(klass.status(download_path)).to eq("")

        with_env(HOMEBREW_DEVELOPER: nil) do
          klass.cask!(cask:, download_path:)
        end

        expect(klass.status(download_path)).to match(
          /\A[0-9a-f]{4};[0-9a-f]+;(?:Homebrew\\x20Cask)?;[0-9A-F-]{36}\z/i,
        )
      end
    end

    it "raises when the quarantine properties cannot be written" do
      mktmpdir do |tmpdir|
        download_path = tmpdir/"missing.dmg"

        expect do
          with_env(HOMEBREW_DEVELOPER: nil) do
            klass.cask!(cask:, download_path:)
          end
        end.to raise_error(Cask::CaskQuarantineError, /Failed to set quarantine properties/)
      end
    end

    it "uses FFI quarantining by default" do
      require "os/mac/ffi"

      download_path = Pathname("/tmp/Test.dmg")
      path = instance_double(Fiddle::Pointer, null?: false)
      url = instance_double(Fiddle::Pointer, null?: false)
      agent_name = instance_double(Fiddle::Pointer, null?: false)
      data_url = instance_double(Fiddle::Pointer, null?: false)
      origin_url = instance_double(Fiddle::Pointer, null?: false)
      dictionary = instance_double(Fiddle::Pointer, null?: false)
      quarantine_properties_key = instance_double(Fiddle::Pointer)

      allow(klass).to receive(:detect).with(download_path).and_return(false)
      allow(MacOS::FFI::CoreFoundation).to receive(:release)
      allow(MacOS::FFI::CoreFoundation).to receive(:string_create).with(download_path.to_s).and_return(path)
      allow(MacOS::FFI::CoreFoundation).to receive(:url_create_with_file_system_path).with(path).and_return(url)
      allow(MacOS::FFI::CoreFoundation).to receive(:string_create).with("Homebrew Cask").and_return(agent_name)
      allow(MacOS::FFI::CoreFoundation).to receive(:string_create).with("https://example.com/download")
                                                                  .and_return(data_url)
      allow(MacOS::FFI::CoreFoundation).to receive(:string_create).with("https://example.com")
                                                                  .and_return(origin_url)
      allow(MacOS::FFI::LaunchServices).to receive_messages(
        quarantine_agent_name_key:    instance_double(Fiddle::Pointer),
        quarantine_type_key:          instance_double(Fiddle::Pointer),
        quarantine_type_web_download: instance_double(Fiddle::Pointer),
        quarantine_data_url_key:      instance_double(Fiddle::Pointer),
        quarantine_origin_url_key:    instance_double(Fiddle::Pointer),
      )
      expect(MacOS::FFI::CoreFoundation).to receive(:dictionary_create).with({
        MacOS::FFI::LaunchServices.quarantine_agent_name_key => agent_name,
        MacOS::FFI::LaunchServices.quarantine_type_key       => MacOS::FFI::LaunchServices.quarantine_type_web_download,
        MacOS::FFI::LaunchServices.quarantine_data_url_key   => data_url,
        MacOS::FFI::LaunchServices.quarantine_origin_url_key => origin_url,
      }).and_return(dictionary)
      allow(MacOS::FFI::CoreFoundation).to receive(:url_quarantine_properties_key)
        .and_return(quarantine_properties_key)
      expect(MacOS::FFI::CoreFoundation).to receive(:url_set_resource_property_for_key)
        .with(url, quarantine_properties_key, dictionary)
        .and_return(true)

      with_env(HOMEBREW_DEVELOPER: nil) do
        klass.cask!(cask:, download_path:)
      end
    end
  end

  describe ".propagate" do
    let(:source) { mktmpdir/"download.zip" }
    let(:destination) { mktmpdir }

    before do
      allow(klass).to receive(:available?).and_return(true)
    end

    it "does nothing when the source is not quarantined" do
      allow(klass).to receive(:status).with(source).and_return("")
      expect(klass).not_to receive(:system_command!)

      klass.propagate(from: source, to: destination)
    end

    it "reads the source metadata once when propagating quarantine" do
      allow(klass).to receive(:system_command!)
      allow(klass).to receive_messages(
        xattr:          Pathname("/usr/bin/xattr"),
        system_command: instance_double(SystemCommand::Result, success?: true),
      )
      expect(klass).to receive(:status).with(source).once.and_return("0083;6723b9fa;Safari;event-id")

      klass.propagate(from: source, to: destination)
    end
  end

  describe ".copy_xattrs", :needs_macos do
    it "uses FFI when the destination is writable" do
      require "os/mac/ffi"

      source = Pathname("/tmp/Source.app")
      destination = Pathname("/tmp/Destination.app")
      command = class_double(SystemCommand)

      allow(destination).to receive(:writable?).and_return(true)
      expect(MacOS::FFI).to receive(:copy_xattrs).with(source.to_s, destination.to_s)

      with_env(HOMEBREW_DEVELOPER: nil) do
        klass.copy_xattrs(source, destination, command:)
      end
    end

    it "uses FFI through vendored Ruby with optional elevation" do
      require "os/mac/ffi"

      source = Pathname("/tmp/Source.app")
      destination = Pathname("/tmp/Destination.app")
      command = class_double(SystemCommand)
      ruby, *args = HOMEBREW_RUBY_EXEC_ARGS

      allow(destination).to receive(:writable?).and_return(false)
      expect(command).to receive(:run!).with(
        ruby,
        args: args + [
          "-I",
          $LOAD_PATH.join(File::PATH_SEPARATOR),
          OS::Mac::Cask::Quarantine::COPY_XATTRS_SCRIPT,
          source,
          destination,
        ],
        sudo: nil,
      )

      with_env(HOMEBREW_DEVELOPER: nil) do
        klass.copy_xattrs(source, destination, command:)
      end
    end

    it "copies extended attributes when run as a standalone script" do
      require "os/mac/ffi"

      mktmpdir do |tmpdir|
        source = tmpdir/"source"
        destination = tmpdir/"destination"
        source.write("source")
        destination.write("destination")
        MacOS::FFI.set_xattr(source.to_s, "com.homebrew.test.source", "source")

        _, stderr, status = Open3.capture3(
          *HOMEBREW_RUBY_EXEC_ARGS,
          "-I", $LOAD_PATH.join(File::PATH_SEPARATOR),
          OS::Mac::Cask::Quarantine::COPY_XATTRS_SCRIPT.to_s,
          source.to_s,
          destination.to_s
        )

        expect(status).to be_success, stderr
        expect(MacOS::FFI.get_xattr(destination.to_s, "com.homebrew.test.source")).to eq("source")
      end
    end
  end

  describe ".user_approved?" do
    let(:file) { Pathname("/tmp/Test.app") }

    before do
      allow(klass).to receive(:xattr).and_return(Pathname("/usr/bin/xattr"))
    end

    it "does not locate xattr when quarantine is unavailable" do
      allow(klass).to receive(:available?).and_return(false)
      expect(klass).not_to receive(:xattr)

      klass.user_approved?(file)
    end

    it "returns true when the user approval flag is set" do
      allow(klass).to receive(:status).with(file).and_return("01c3;6723b9fa;Safari;event-id")

      expect(klass.user_approved?(file)).to be(true)
    end

    it "returns false when the user approval flag is not set" do
      allow(klass).to receive(:status).with(file).and_return("0183;6723b9fa;Safari;event-id")

      expect(klass.user_approved?(file)).to be(false)
    end
  end

  describe ".inherit_user_approval!" do
    let(:file) { Pathname("/tmp/Test.app") }
    let(:xattr) { Pathname("/usr/bin/xattr") }

    it "sets the user approval flag while preserving the quarantine metadata" do
      allow(klass).to receive_messages(
        detect: true,
        status: "0381;6a51855d;;3C86362A-29CA-4D55-90E7-A6621B9CC78D",
        xattr:,
      )
      expect(klass).to receive(:system_command).with(
        "/usr/bin/xargs",
        args:         [
          "-0",
          "--",
          xattr,
          "-w",
          Cask::Quarantine::QUARANTINE_ATTRIBUTE,
          "03c1;6a51855d;;3C86362A-29CA-4D55-90E7-A6621B9CC78D",
        ],
        input:        file.to_s,
        print_stderr: false,
      ).and_return(instance_double(SystemCommand::Result, success?: true))

      klass.inherit_user_approval!(download_path: file)
    end

    it "mirrors approval onto shared paths and skips paths this version does not have" do
      mktmpdir do |tmpdir|
        app = tmpdir/"Test.app"
        (app/"Contents/MacOS").mkpath
        FileUtils.touch app/"Contents/MacOS/Test"

        allow(klass).to receive_messages(
          detect: true,
          status: "0381;6a51855d;;3C86362A-29CA-4D55-90E7-A6621B9CC78D",
          xattr:,
        )
        expect(klass).to receive(:system_command).with(
          "/usr/bin/xargs",
          args:         [
            "-0",
            "--",
            xattr,
            "-w",
            Cask::Quarantine::QUARANTINE_ATTRIBUTE,
            "03c1;6a51855d;;3C86362A-29CA-4D55-90E7-A6621B9CC78D",
          ],
          input:        [app, app/"Contents/MacOS/Test"].join("\0"),
          print_stderr: false,
        ).and_return(instance_double(SystemCommand::Result, success?: true))

        klass.inherit_user_approval!(download_path:  app,
                                     approved_paths: ["Contents/MacOS/Test", "Contents/MacOS/Removed"])
      end
    end
  end

  describe ".user_approved_paths" do
    let(:xattr) { Pathname("/usr/bin/xattr") }

    it "returns only the approved paths, relative to the directory" do
      mktmpdir do |tmpdir|
        app = tmpdir/"Test.app"
        (app/"Contents").mkpath
        FileUtils.touch app/"Contents/approved"
        FileUtils.touch app/"Contents/unapproved"

        allow(klass).to receive_messages(xattr: xattr, system_command: instance_double(
          SystemCommand::Result,
          stdout: "#{app}: 03c1;6a51855d;;uuid\n" \
                  "#{app}/Contents: 0381;6a51855d;;uuid\n" \
                  "#{app}/Contents/approved: 03c1;6a51855d;;uuid\n" \
                  "#{app}/Contents/unapproved: 0381;6a51855d;;uuid\n",
        ))

        expect(klass.user_approved_paths(app)).to eq(["Contents/approved"])
      end
    end
  end

  describe ".signing_identity", :needs_macos do
    let(:file) { Pathname("/tmp/Test.app") }
    let(:requirement) do
      'identifier "sh.brew.test-app" and anchor apple generic and certificate leaf[subject.OU] = "ABCDE12345"'
    end

    it "returns the validated designated requirement without invoking codesign" do
      allow(MacOS::FFI::Security).to receive(:designated_requirement).with(file.to_s).and_return(requirement)
      expect(klass).not_to receive(:system_command)

      expect(klass.signing_identity(file)).to have_attributes(requirement:)
    end

    it "returns nil when the signature cannot be verified" do
      allow(MacOS::FFI::Security).to receive(:designated_requirement).with(file.to_s).and_return(nil)

      expect(klass.signing_identity(file)).to be_nil
    end
  end

  describe ".signing_identity_match", :needs_macos do
    let(:file) { Pathname("/tmp/Test.app") }
    let(:requirement) { 'identifier "sh.brew.test-app" and anchor apple' }
    let(:identity) { Cask::Quarantine::SigningIdentity.new(requirement:) }

    it "checks the new app against the previous version's designated requirement" do
      expect(MacOS::FFI::Security).to receive(:requirement_match).with(file.to_s, requirement).and_return(true)

      expect(klass.signing_identity_match(file, identity)).to be(true)
    end
  end
end
