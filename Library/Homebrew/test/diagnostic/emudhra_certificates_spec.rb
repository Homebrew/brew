# typed: true
# frozen_string_literal: true

require "diagnostic"
require "open3"
require "openssl"

RSpec.describe Homebrew::Diagnostic::Checks do
  sig { params(common_name: String).returns(String) }
  def certificate_pem(common_name)
    key = OpenSSL::PKey::EC.generate("prime256v1")
    certificate = OpenSSL::X509::Certificate.new
    certificate.subject = certificate.issuer = OpenSSL::X509::Name.new([["CN", common_name]])
    certificate.public_key = key
    certificate.not_before = certificate.not_after = Time.now
    certificate.sign(key, "SHA256").to_pem
  end

  sig {
    params(bundle: Pathname, os: String, euid: Integer, backup_failure: T::Boolean, sync_failure: T.nilable(String))
      .returns([String, String, Process::Status])
  }
  def run_mitigation(bundle, os: "Darwin", euid: 0, backup_failure: false, sync_failure: nil)
    script = (HOMEBREW_LIBRARY_PATH/"utils/emudhra_certificates.rb").read
    script = script.sub('cert_file = "/etc/ssl/cert.pem"', "cert_file = #{bundle.to_s.inspect}")
                   .sub('RUBY_PLATFORM.include?("darwin")', (os == "Darwin").to_s)
                   .sub("Process.euid.zero?", euid.zero?.to_s)
    raise "Unsafe test script" if script.include?("/etc/ssl/")

    if backup_failure
      script.prepend <<~RUBY
        require "fileutils"
        module FileUtils
          def self.cp(_source, destination, **)
            File.write(destination, "partial backup")
            raise Errno::ENOSPC
          end
        end
      RUBY
    end
    if sync_failure
      script.prepend <<~RUBY
        class File
          def fsync
            raise Errno::EIO if path.end_with?(#{sync_failure.inspect})

            super
          end
        end
      RUBY
    end
    Open3.capture3(*HOMEBREW_RUBY_EXEC_ARGS, "-e", script)
  end

  describe "#certificate_trust_check" do
    subject(:finding) do
      described_class.new.certificate_trust_check(
        "/etc/ssl/cert.pem",
        root_names:   ["emSign ECC Root CA - G3", "AAA Certificate Services"],
        advisory_url: "https://support.apple.com/en-us/149555",
        script:       (HOMEBREW_LIBRARY_PATH/"utils/emudhra_certificates.rb").to_s.shellescape,
      )
    end

    before do
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("/etc/ssl/cert.pem").and_return(certificate_pem("Unaffected Root CA"))
    end

    test_each([
      ["emSign ECC Root CA - G3"],
      ["AAA Certificate Services"],
      ["emSign ECC Root CA - G3", "AAA Certificate Services"],
    ]) do |roots|
      it "warns when #{roots.join(" and ")} remains trusted" do
        allow(File).to receive(:read).with("/etc/ssl/cert.pem")
                                     .and_return(roots.map { |root| certificate_pem(root) }.join)

        expect(finding&.to_s).to include(*roots)
      end
    end

    it "recommends Homebrew's Ruby with sudo and formats commands as code" do
      allow(File).to receive(:read).with("/etc/ssl/cert.pem")
                                   .and_return(certificate_pem("emSign ECC Root CA - G3"))
      script = (HOMEBREW_LIBRARY_PATH/"utils/emudhra_certificates.rb").to_s.shellescape

      expect(finding&.remediation&.to_s)
        .to include("sudo #{RUBY_PATH.to_s.shellescape} --disable=gems,rubyopt #{script}",
                    "backup", "`brew doctor`", "HTTPS connections", "system updates")
    end

    it "recommends running all doctor checks after mitigation" do
      allow(File).to receive(:read).with("/etc/ssl/cert.pem")
                                   .and_return(certificate_pem("emSign ECC Root CA - G3"))

      expect(finding&.remediation&.to_s).not_to include("brew doctor check_")
    end

    it "does not warn when neither root is trusted" do
      expect(finding).to be_nil
    end

    it "ignores certificate names left in comments after removal" do
      allow(File).to receive(:read).with("/etc/ssl/cert.pem").and_return(
        "### emSign ECC Root CA - G3\n### AAA Certificate Services\n#{certificate_pem("Unaffected Root CA")}",
      )

      expect(finding).to be_nil
    end

    it "skips a missing system bundle" do
      allow(File).to receive(:read).with("/etc/ssl/cert.pem").and_raise(Errno::ENOENT)

      expect(finding).to be_nil
    end

    it "reports an unreadable system bundle" do
      allow(File).to receive(:read).with("/etc/ssl/cert.pem").and_raise(Errno::EACCES)

      expect(finding&.to_s).to include("Could not check /etc/ssl/cert.pem")
    end

    it "reports an invalid system bundle" do
      allow(File).to receive(:read).with("/etc/ssl/cert.pem").and_return("invalid certificate bundle")

      expect(finding&.to_s).to include("Could not check /etc/ssl/cert.pem")
    end
  end

  describe "#check_for_emudhra_certificates", :needs_macos do
    subject(:checks) { described_class.new }

    it "selects the affected roots and mitigation" do
      ENV.delete("GITHUB_ACTIONS")

      expect(checks).to receive(:certificate_trust_check).with(
        "/etc/ssl/cert.pem",
        root_names:   ["emSign ECC Root CA - G3", "AAA Certificate Services"],
        advisory_url: "https://support.apple.com/en-us/149555",
        script:       (HOMEBREW_LIBRARY_PATH/"utils/emudhra_certificates.rb").to_s.shellescape,
      )

      checks.check_for_emudhra_certificates
    end

    it "skips GitHub Actions runners" do
      ENV["GITHUB_ACTIONS"] = "true"

      expect(checks).not_to receive(:certificate_trust_check)

      checks.check_for_emudhra_certificates
    end
  end

  describe "utils/emudhra_certificates" do
    it "removes both roots while preserving unrelated certificates" do
      bundle = mktmpdir/"cert.pem"
      unaffected = certificate_pem("Unaffected Root CA")
      bundle.write ["Unaffected Root CA", "emSign ECC Root CA - G3", "AAA Certificate Services"].map { |name|
        certificate = if name == "Unaffected Root CA"
          unaffected
        else
          certificate_pem(name)
        end
        "=== /CN=#{name}\n#{certificate}"
      }.join + "=== /CN=Unaffected Root CA\n#{unaffected}"
      original = bundle.read
      _, _, status = run_mitigation(bundle)

      expect([status.success?, OpenSSL::X509::Certificate.load(bundle.read).map(&:to_pem),
              Pathname("#{bundle}.orig").read, Pathname("#{bundle}.bak").read])
        .to eq([true, [unaffected, unaffected], original, original])
    end

    it "preserves an existing backup when run repeatedly" do
      bundle = mktmpdir/"cert.pem"
      unaffected = certificate_pem("Unaffected Root CA")
      bundle.write "=== /CN=emSign ECC Root CA - G3\n#{certificate_pem("emSign ECC Root CA - G3")}" \
                   "=== /CN=Unaffected Root CA\n#{unaffected}"
      Pathname("#{bundle}.orig").write "original backup"
      original = bundle.read

      statuses = Array.new(2) { run_mitigation(bundle).last.success? }

      expect([statuses, OpenSSL::X509::Certificate.load(bundle.read).map(&:to_pem),
              Pathname("#{bundle}.orig").read, Pathname("#{bundle}.bak").read])
        .to eq([[true, true], [unaffected], "original backup", original])
    end

    it "backs up the current bundle after a macOS update while retaining the first backup" do
      bundle = mktmpdir/"cert.pem"
      original = certificate_pem("emSign ECC Root CA - G3") + certificate_pem("Unaffected Root CA")
      bundle.write original
      run_mitigation(bundle)
      updated = certificate_pem("AAA Certificate Services") + certificate_pem("New Root CA")
      bundle.write updated

      stdout, _, status = run_mitigation(bundle)

      expect([status.success?, Pathname("#{bundle}.orig").read, Pathname("#{bundle}.bak").read,
              stdout.include?("sudo cp -p #{bundle}.bak #{bundle}")]).to eq([true, original, updated, true])
    end

    it "rejects trusted certificate entries without changing the bundle or backups" do
      bundle = mktmpdir/"cert.pem"
      trusted = certificate_pem("Trusted Root CA").gsub("CERTIFICATE", "TRUSTED CERTIFICATE")
      original = certificate_pem("emSign ECC Root CA - G3") + certificate_pem("Unaffected Root CA") + trusted
      bundle.write original

      _, stderr, status = run_mitigation(bundle)

      expect([status.success?, bundle.read, Pathname("#{bundle}.orig").exist?, Pathname("#{bundle}.bak").exist?,
              stderr.include?("TRUSTED CERTIFICATE")]).to eq([false, original, false, false, true])
    end

    test_each(["", "invalid bundle", "### Empty bundle\n"]) do |contents|
      it "rejects #{contents.inspect} without replacing the bundle" do
        bundle = mktmpdir/"cert.pem"
        bundle.write contents

        _, _, status = run_mitigation(bundle)

        expect([status.success?, bundle.read, Pathname("#{bundle}.orig").exist?]).to eq([false, contents, false])
      end
    end

    it "removes roots from a bundle without Apple text headings" do
      bundle = mktmpdir/"cert.pem"
      unaffected = certificate_pem("Unaffected Root CA")
      bundle.write certificate_pem("emSign ECC Root CA - G3") + unaffected

      _, _, status = run_mitigation(bundle)

      expect([status.success?, bundle.read]).to eq([true, unaffected])
    end

    it "does not publish a partial backup or reuse it on retry" do
      bundle = mktmpdir/"cert.pem"
      bundle.write "=== /CN=emSign ECC Root CA - G3\n#{certificate_pem("emSign ECC Root CA - G3")}" \
                   "=== /CN=Unaffected Root CA\n#{certificate_pem("Unaffected Root CA")}"
      original = bundle.read

      _, _, status = run_mitigation(bundle, backup_failure: true)
      failed_attempt = [status.success?, bundle.read, Pathname("#{bundle}.orig").exist?,
                        Pathname("#{bundle}.bak").exist?]

      _, _, status = run_mitigation(bundle)

      expect([failed_attempt, status.success?, Pathname("#{bundle}.orig").read, Pathname("#{bundle}.bak").read])
        .to eq([[false, original, false, false], true, original, original])
    end

    test_each([".pem", ".bak"]) do |suffix|
      it "leaves the bundle and backups untouched if syncing the staged #{suffix} file fails" do
        bundle = mktmpdir/"cert.pem"
        original = certificate_pem("emSign ECC Root CA - G3") + certificate_pem("Unaffected Root CA")
        bundle.write original

        _, _, status = run_mitigation(bundle, sync_failure: suffix)

        expect([status.success?, bundle.read, Pathname("#{bundle}.orig").exist?, Pathname("#{bundle}.bak").exist?])
          .to eq([false, original, false, false])
      end
    end

    it "rejects Linux before reading the bundle" do
      _, stderr, status = run_mitigation(mktmpdir/"missing.pem", os: "Linux")

      expect([status.success?, stderr]).to eq([false, "Error: This script only supports macOS.\n"])
    end

    it "requires sudo before reading the bundle" do
      _, stderr, status = run_mitigation(mktmpdir/"missing.pem", euid: 1000)

      expect([status.success?, stderr]).to eq([false, "Error: Run this script with sudo.\n"])
    end
  end
end
