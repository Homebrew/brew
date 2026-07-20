# typed: strict
# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::InstallSteps, :config do
  it "allows a flight block after matching steps during migration" do
    expect_no_offenses <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight_steps do
          touch "foo"
        end

        postflight do
          touch "foo"
        end
      end
    CASK
  end

  it "reports an offense when a steps block contains Ruby code" do
    expect_offense <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        preflight_steps do
          system "true"
          ^^^^^^^^^^^^^ Steps blocks may only contain install step DSL calls: `mkdir_p`, `touch`, `move`, `move_contents`, `copy`, `remove`, `inreplace`, `symlink`, `write_file`, `delete_keychain_certificates`, `set_permissions`, `set_ownership`, `run`, `terminate_process`, `if_path_exists`, `unless_path_exists`, `on_macos`, `on_linux`.
        end
      end
    CASK
  end

  it "reports an offense when cask steps contain formula rebuild actions" do
    expect_offense <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        preflight_steps do
          update_desktop_database
          ^^^^^^^^^^^^^^^^^^^^^^^ Steps blocks may only contain install step DSL calls: `mkdir_p`, `touch`, `move`, `move_contents`, `copy`, `remove`, `inreplace`, `symlink`, `write_file`, `delete_keychain_certificates`, `set_permissions`, `set_ownership`, `run`, `terminate_process`, `if_path_exists`, `unless_path_exists`, `on_macos`, `on_linux`.
        end
      end
    CASK
  end

  it "accepts install step DSL calls" do
    expect_no_offenses <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        preflight_steps do
          mkdir_p "foo"
          touch "foo/state"
          move "source", "target"
          move_contents "source", "target"
          inreplace "foo.conf", "@PREFIX@", "{{HOMEBREW_PREFIX}}"
          symlink "source", "target", source_base: :relative, overwrite: true, remove_on_uninstall: true
          write_file "foo.conf", "key = value\n"
          set_permissions "Foo.app", "0755"
          set_ownership "Foo.app", user: "root", group: "wheel"
          run "foo", args: ["--repair"]
          terminate_process "foo", attempts: 3
          delete_keychain_certificates "Charles"
          delete_keychain_certificates "NodeMITMProxyCA", fingerprint_of: "~/Library/Application Support/betwixt/ssl/certs/ca.pem"
          on_macos do
            if_path_exists "Foo.app" do
              touch "Foo.app/marker"
            end
          end
        end
      end
    CASK
  end

  it "autocorrects simple flight block file preparation" do
    expect_offense <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight do
        ^^^^^^^^^^^^^ Use `postflight_steps` for simple file preparation.
          (staged_path/"Prepared").mkpath
          FileUtils.touch staged_path/"Prepared/touched"
          FileUtils.mv staged_path/"source", staged_path/"target"
          FileUtils.ln_s "target", staged_path/"Linked"
        end
      end
    CASK

    expect_correction <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight_steps do
          mkdir_p "Prepared"
          touch "Prepared/touched"
          move "source", "target"
          symlink "target", "Linked", source_base: :relative
        end
      end
    CASK
  end

  it "autocorrects simple flight block config writes" do
    expect_offense <<~'CASK'
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight do
        ^^^^^^^^^^^^^ Use `postflight_steps` for simple file preparation.
          File.write staged_path/"Prepared/foo.conf", "key = value\n"
        end
      end
    CASK

    expect_correction <<~'CASK'
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight_steps do
          write_file "Prepared/foo.conf", "key = value\n"
        end
      end
    CASK
  end

  it "autocorrects fixed keychain certificate deletion flight blocks" do
    expect_offense <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        preflight do
        ^^^^^^^^^^^^ Use `preflight_steps` for simple file preparation.
          stdout, * = system_command "/usr/bin/security",
                                     args: ["find-certificate", "-a", "-c", "Charles", "-Z"],
                                     sudo: true
          hashes = stdout.lines.grep(/^SHA-256 hash:/) { |l| l.split(":").second.strip }
          hashes.each do |h|
            system_command "/usr/bin/security",
                           args: ["delete-certificate", "-Z", h],
                           sudo: true
          end
        end

        postflight do
        ^^^^^^^^^^^^^ Use `postflight_steps` for simple file preparation.
          ["AutoFirma ROOT", "127.0.0.1"].each do |cert_name|
            stdout, * = system_command "/usr/bin/security",
                                       args: ["find-certificate", "-a", "-c", cert_name, "-Z"],
                                       sudo: true
            hashes = stdout.lines.grep(/^SHA-256 hash:/) { |l| l.split(":").second.strip }
            hashes.each do |h|
              system_command "/usr/bin/security",
                             args: ["delete-certificate", "-Z", h],
                             sudo: true
            end
          end
        end

        uninstall_postflight do
        ^^^^^^^^^^^^^^^^^^^^^^^ Use `uninstall_postflight_steps` for simple file preparation.
          cert = Pathname("~/Library/Application Support/betwixt/ssl/certs/ca.pem").expand_path
          next unless cert.exist?

          stdout, * = system_command "/usr/bin/openssl",
                                     args: ["x509", "-fingerprint", "-sha256", "-noout", "-in", cert]
          hash = stdout.lines.first.split("=").second.delete(":").strip
          stdout, * = system_command "/usr/bin/security",
                                     args: ["find-certificate", "-a", "-c", "NodeMITMProxyCA", "-Z"],
                                     sudo: true
          hashes = stdout.lines.grep(/^SHA-256 hash:/) { |l| l.split(":").second.strip }
          if hashes.include?(hash)
            system_command "/usr/bin/security",
                           args: ["delete-certificate", "-Z", hash],
                           sudo: true
          end
        end
      end
    CASK

    expect_correction <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        preflight_steps do
          delete_keychain_certificates "Charles"
        end

        postflight_steps do
          delete_keychain_certificates "AutoFirma ROOT"
          delete_keychain_certificates "127.0.0.1"
        end

        uninstall_postflight_steps do
          delete_keychain_certificates "NodeMITMProxyCA",
                                       fingerprint_of: "~/Library/Application Support/betwixt/ssl/certs/ca.pem"
        end
      end
    CASK
  end

  it "does not autocorrect altered or mixed keychain deletion blocks" do
    expect_no_offenses <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        uninstall_postflight do
          stdout, * = system_command "/usr/local/bin/security",
                                     args: ["find-certificate", "-a", "-c", "Charles", "-Z"],
                                     sudo: true
          hashes = stdout.lines.grep(/^SHA-256 hash:/) { |l| l.split(":").second.strip }
          hashes.each do |h|
            system_command "/usr/local/bin/security",
                           args: ["delete-certificate", "-Z", h],
                           sudo: true
          end
        end
      end
    CASK

    expect_no_offenses <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        uninstall_postflight do
          stdout, * = system_command "/usr/bin/security",
                                     args: ["find-certificate", "-a", "-c", "Charles", "-Z", "login.keychain"],
                                     sudo: true
          hashes = stdout.lines.grep(/^SHA-256 hash:/) { |l| l.split(":").second.strip }
          hashes.each do |h|
            system_command "/usr/bin/security",
                           args: ["delete-certificate", "-Z", h],
                           sudo: true
          end
        end
      end
    CASK

    expect_no_offenses <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        uninstall_postflight do
          stdout, * = system_command "/usr/bin/security",
                                     args: ["find-certificate", "-a", "-c", "Charles", "-Z"],
                                     sudo: true
          hashes = stdout.lines.grep(/^SHA-256 hash:/) { |l| l.split(":").second.strip }
          hashes.each do |h|
            system_command "/usr/bin/security",
                           args: ["delete-certificate", "-Z", h],
                           sudo: true
          end
          system_command "/usr/bin/true"
        end
      end
    CASK
  end

  it "does not re-report declarative keychain, permission or ownership steps" do
    expect_no_offenses <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        uninstall_postflight_steps do
          delete_keychain_certificates "Charles"
          set_permissions "Foo.app", "0755"
          set_ownership "Foo.app", user: "root", group: "wheel"
        end
      end
    CASK
  end

  it "autocorrects pure permission and ownership flight blocks" do
    expect_offense <<~'CASK'
      cask "foo" do
        version :latest
        sha256 :no_check

        preflight do
        ^^^^^^^^^^^^ Use `preflight_steps` for simple file preparation.
          set_permissions "#{staged_path}/Foo.app", "0755"
        end

        postflight do
        ^^^^^^^^^^^^^ Use `postflight_steps` for simple file preparation.
          set_permissions "#{appdir}/Foo.app", "0555"
          set_ownership "#{HOMEBREW_PREFIX}/foo"
        end

        uninstall_preflight do
        ^^^^^^^^^^^^^^^^^^^^^^ Use `uninstall_preflight_steps` for simple file preparation.
          set_ownership ["/usr/local/include", "/usr/local/lib"], user: "root", group: "wheel"
        end

        uninstall_postflight do
        ^^^^^^^^^^^^^^^^^^^^^^^ Use `uninstall_postflight_steps` for simple file preparation.
          set_ownership staged_path.to_s
        end
      end
    CASK

    expect_correction <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        preflight_steps do
          set_permissions "Foo.app", "0755"
        end

        postflight_steps do
          set_permissions "Foo.app", "0555", base: :appdir
          set_ownership "foo", base: :homebrew_prefix
        end

        uninstall_preflight_steps do
          set_ownership ["/usr/local/include", "/usr/local/lib"], user: "root", group: "wheel"
        end

        uninstall_postflight_steps do
          set_ownership "."
        end
      end
    CASK
  end

  it "does not autocorrect dynamic, unsupported or mixed permission work" do
    expect_no_offenses <<~'CASK'
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight do
          set_ownership "#{staged_path}/foo-#{arch}"
        end
      end
    CASK

    expect_no_offenses <<~'CASK'
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight do
          set_permissions "#{staged_path}/Foo.app", "0755", recursive: false
        end
      end
    CASK

    expect_no_offenses <<~'CASK'
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight do
          set_ownership ["#{staged_path}/Foo.app", "#{appdir}/Foo.app"]
        end
      end
    CASK

    expect_no_offenses <<~'CASK'
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight do
          set_permissions "#{staged_path}/Foo.app", "0755"
          system_command "/usr/bin/true"
        end
      end
    CASK
  end

  it "autocorrects config writes without trailing newlines" do
    expect_offense <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight do
        ^^^^^^^^^^^^^ Use `postflight_steps` for simple file preparation.
          File.write staged_path/"Prepared/foo.conf", "key = value"
        end
      end
    CASK

    expect_correction <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight_steps do
          write_file "Prepared/foo.conf", "key = value"
        end
      end
    CASK
  end

  it "does not autocorrect non-file preparation in flight blocks" do
    expect_no_offenses <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight do
          system_command "/usr/bin/true"
        end
      end
    CASK
  end

  it "does not autocorrect formula rebuild actions in flight blocks" do
    expect_no_offenses <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight do
          system Formula["desktop-file-utils"].opt_bin/"update-desktop-database", HOMEBREW_PREFIX/"share/applications"
        end
      end
    CASK
  end
end
