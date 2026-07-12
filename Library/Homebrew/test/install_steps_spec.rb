# typed: false
# frozen_string_literal: true

require "install_steps"
require "cask/quarantine"

RSpec.describe Homebrew::InstallSteps do
  let(:root) { Pathname(TEST_TMPDIR)/"install-steps" }
  let(:context) do
    root_path = root
    Class.new do
      define_method(:prefix) { root_path/"prefix" }
      define_method(:bin) { root_path/"prefix/bin" }
      define_method(:var) { root_path/"var" }
      define_method(:staged_path) { root_path/"stage" }
    end.new
  end

  before do
    FileUtils.rm_rf root
  end

  after do
    FileUtils.rm_rf root
  end

  specify "runs mkdir, touch, move and symlink steps", :aggregate_failures do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var, default_source_base: :staged_path,
                                              default_target_base: :staged_path) do
      mkdir_p "log/example"
      touch "state/marker", base: :prefix
      mv "move-source", "move-target"
      ln_s "move-target", "linked-target", source_base: :relative
    end

    (root/"stage").mkpath
    (root/"stage/move-source").write "moved"

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect(root/"var/log/example").to be_a_directory
    expect(root/"prefix/state/marker").to exist
    expect(root/"stage/move-target").to exist
    expect(root/"stage/linked-target").to be_a_symlink
    expect((root/"stage/linked-target").readlink).to eq(Pathname("move-target"))
  end

  specify "runs mkdir without creating parent directories" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      mkdir "missing-parent/example"
    end

    expect(steps).to include(
      "type" => "mkdir",
      "path" => {
        "base" => "var",
        "path" => "missing-parent/example",
      },
    )
    expect { Homebrew::InstallSteps::Runner.new(context:).run(steps) }.to raise_error(Errno::ENOENT)
  end

  specify "runs mkdir_p recursively" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      mkdir_p "nested/example"
    end

    expect(steps).to include(
      "type" => "mkdir_p",
      "path" => {
        "base" => "var",
        "path" => "nested/example",
      },
    )

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect(root/"var/nested/example").to be_a_directory
  end

  specify "normalises API step keys and values" do
    steps = [
      {
        type: :mkdir_p,
        path: {
          base: :var,
          path: "nested/example",
        },
      },
      {
        type:                 :delete_keychain_certificate,
        name:                 "NodeMITMProxyCA",
        matching_certificate: "~/Library/Application Support/betwixt/ssl/certs/ca.pem",
      },
      {
        type:        :set_permissions,
        paths:       ["Example.app"],
        permissions: "0755",
      },
      {
        type:  :set_ownership,
        paths: [{ base: :staged_path, path: "Example.app" }],
        user:  :root,
        group: :wheel,
      },
    ]

    expect(Homebrew::InstallSteps::DSL.normalise_steps(steps)).to contain_exactly(
      {
        "type" => "mkdir_p",
        "path" => {
          "base" => "var",
          "path" => "nested/example",
        },
      },
      {
        "type"                 => "delete_keychain_certificate",
        "name"                 => "NodeMITMProxyCA",
        "matching_certificate" => {
          "path" => "~/Library/Application Support/betwixt/ssl/certs/ca.pem",
        },
      },
      {
        "type"        => "set_permissions",
        "paths"       => [{ "path" => "Example.app" }],
        "permissions" => "0755",
      },
      {
        "type"  => "set_ownership",
        "paths" => [{
          "base" => "staged_path",
          "path" => "Example.app",
        }],
        "user"  => "root",
        "group" => "wheel",
      },
    )
  end

  specify "expands a scoped set of content tokens and leaves others verbatim", :aggregate_failures do
    root_path = root
    versioned_context = Class.new do
      define_method(:prefix) { root_path/"prefix" }
      define_method(:version) { Version.new("1.2.3") }
    end.new

    steps = Homebrew::InstallSteps::DSL.build(default_base: :prefix) do
      write "config.ini", <<~EOS
        prefix = {{prefix}}
        cellar = {{HOMEBREW_PREFIX}}
        series = {{version.major_minor}} ({{version}})
        literal = {{unknown}} {single}
      EOS
    end

    Homebrew::InstallSteps::Runner.new(context: versioned_context).run(steps)

    written = (root/"prefix/config.ini").read
    expect(written).to include("prefix = #{root}/prefix")
    expect(written).to include("cellar = #{HOMEBREW_PREFIX}")
    expect(written).to include("series = 1.2 (1.2.3)")
    expect(written).to include("literal = {{unknown}} {single}")
  end

  specify "writes a default config file and preserves existing ones", :aggregate_failures do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      write "config/new.conf", "fresh"
      write "config/kept.conf", "default"
      write "config/replaced.conf", "default", overwrite: true
    end

    (root/"var/config").mkpath
    (root/"var/config/kept.conf").write "user edit"
    (root/"var/config/replaced.conf").write "user edit"

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect((root/"var/config/new.conf").read).to eq("fresh\n")
    expect((root/"var/config/kept.conf").read).to eq("user edit")
    expect((root/"var/config/replaced.conf").read).to eq("default\n")
  end

  specify "appends a trailing newline unless already present", :aggregate_failures do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      write "missing-newline", "value"
      write "has-newline", "value\n"
    end

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect((root/"var/missing-newline").read).to eq("value\n")
    expect((root/"var/has-newline").read).to eq("value\n")
  end

  specify "raises when a write step has missing or blank content" do
    expect do
      Homebrew::InstallSteps::Runner.new(context:).run([{ "type" => "write", "path" => "config/new.conf" }])
    end.to raise_error(ArgumentError, /non-empty content/)
  end

  specify "runs service data directory initialisers", :aggregate_failures do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      init_data_dir "postgresql@16", using: :postgresql_initdb
      init_data_dir "postgresql@12", using: :postgresql_initdb, locale: "C"
      init_data_dir "mysql", using: :mysql_initialize
      init_data_dir "mysql", using: :mariadb_install_db
    end

    runner = Homebrew::InstallSteps::Runner.new(context:)

    expect(runner).to receive(:run_command).with(root/"prefix/bin/initdb", "--locale=en_US.UTF-8", "-E", "UTF-8",
                                                 root/"var/postgresql@16").ordered
    expect(runner).to receive(:run_command).with(root/"prefix/bin/initdb", "--locale=C", "-E", "UTF-8",
                                                 root/"var/postgresql@12").ordered
    expect(runner).to receive(:run_command).with(root/"prefix/bin/mysqld", "--initialize-insecure",
                                                 "--user=#{ENV.fetch("USER")}", "--basedir=#{root}/prefix",
                                                 "--datadir=#{root}/var/mysql", "--tmpdir=/tmp").ordered
    expect(runner).to receive(:run_command).with(root/"prefix/bin/mysql_install_db", "--verbose",
                                                 "--user=#{ENV.fetch("USER")}", "--basedir=#{root}/prefix",
                                                 "--datadir=#{root}/var/mysql", "--tmpdir=/tmp").ordered

    runner.run(steps)

    expect(root/"var/postgresql@16").to be_a_directory
    expect(root/"var/postgresql@12").to be_a_directory
    expect(root/"var/mysql").to be_a_directory
  end

  specify "links remapped directories and children before running initdb", :aggregate_failures do
    homebrew_prefix = root/"homebrew-prefix"
    stub_const("HOMEBREW_PREFIX", homebrew_prefix)
    root_path = root
    versioned_context = Class.new do
      define_method(:name) { "postgresql@17" }
      define_method(:version) { Version.new("17.5") }
      define_method(:prefix) { root_path/"prefix" }
      define_method(:bin) { root_path/"prefix/bin" }
      define_method(:var) { root_path/"var" }
    end.new
    %w[include lib share].each do |dir|
      (root/"prefix/#{dir}/postgresql/server").mkpath
      (root/"prefix/#{dir}/postgresql/server/extension.h").write dir
      (root/"prefix/#{dir}/postgresql/postgres.bki").write dir
      (root/"prefix/#{dir}/postgresql/.DS_Store").write ""
      (homebrew_prefix/dir/"postgresql@17/server").mkpath
      (homebrew_prefix/dir/"postgresql@17/server/local.h").write dir
    end
    (root/"prefix/share/postgresql/conflicting-path").write "source file"
    (homebrew_prefix/"share/postgresql@17/conflicting-path").mkpath
    (homebrew_prefix/"share/postgresql@17/conflicting-path/local").write "kept"
    (root/"prefix/bin").mkpath
    (root/"prefix/bin/initdb").write ""
    FileUtils.chmod "+x", root/"prefix/bin/initdb"
    (root/"prefix/bin/pg_config").write ""
    FileUtils.chmod "+x", root/"prefix/bin/pg_config"

    steps = Homebrew::InstallSteps::DSL.build(default_base: :var, default_source_base: :prefix) do
      link_dir "include/postgresql", "include/#{name}"
      link_dir "lib/postgresql", "lib/#{name}"
      link_dir "share/postgresql", "share/#{name}"
      link_children "bin", suffix: "-#{version.major}"
      init_data_dir name, using: :postgresql_initdb
    end

    runner = Homebrew::InstallSteps::Runner.new(context: versioned_context)

    expect(runner).to receive(:run_command) do |*args|
      expect(args).to eq([root/"prefix/bin/initdb", "--locale=en_US.UTF-8", "-E", "UTF-8",
                          root/"var/postgresql@17"])
      expect(homebrew_prefix/"share/postgresql@17").to be_a_directory
      expect(homebrew_prefix/"share/postgresql@17/postgres.bki").to be_a_symlink
    end

    runner.run(steps)

    %w[include lib share].each do |dir|
      expect(homebrew_prefix/dir/"postgresql@17/server").to be_a_directory
      expect(homebrew_prefix/dir/"postgresql@17/server/local.h").to exist
      expect(homebrew_prefix/dir/"postgresql@17/server/extension.h").to be_a_symlink
      expect(homebrew_prefix/dir/"postgresql@17/postgres.bki").to be_a_symlink
      expect(homebrew_prefix/dir/"postgresql@17/.DS_Store").not_to exist
    end
    expect(homebrew_prefix/"share/postgresql@17/conflicting-path/local").to exist
    expect(homebrew_prefix/"bin/initdb-17").to be_a_symlink
    expect(homebrew_prefix/"bin/pg_config-17").to be_a_symlink
  end

  specify "skips data directory initialisers in CI", :aggregate_failures do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      init_data_dir "postgresql@16", using: :postgresql_initdb
    end

    ENV["HOMEBREW_GITHUB_ACTIONS"] = "1"

    runner = Homebrew::InstallSteps::Runner.new(context:)
    expect(runner).not_to receive(:run_command)

    runner.run(steps)

    expect(root/"var/postgresql@16").to be_a_directory
  end

  specify "skips data directory initialisers when their marker exists", :aggregate_failures do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      init_data_dir "mysql", using: :mysql_initialize
    end

    (root/"var/mysql/mysql").mkpath
    (root/"var/mysql/mysql/general_log.CSM").write ""

    runner = Homebrew::InstallSteps::Runner.new(context:)
    expect(runner).not_to receive(:run_command)

    runner.run(steps)

    expect(root/"var/mysql").to be_a_directory
  end

  specify "raises on unknown data directory initialisers" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      init_data_dir "unknown", using: :unknown_database
    end

    ENV["HOMEBREW_GITHUB_ACTIONS"] = "1"

    expect { Homebrew::InstallSteps::Runner.new(context:).run(steps) }
      .to raise_error(ArgumentError, /unknown data directory initialiser/)
    expect(root/"var/unknown").not_to exist
  end

  specify "runs named desktop and cache rebuild actions" do
    steps = Homebrew::InstallSteps::DSL.build do
      compile_gsettings_schemas
      gio_querymodules
      gdk_pixbuf_query_loaders
      update_mime_database
      update_desktop_database
    end

    formula = instance_double(Formula, opt_bin: root/"opt/bin")
    allow(Formula).to receive(:[]).with("glib").and_return(formula)
    allow(Formula).to receive(:[]).with("gdk-pixbuf").and_return(formula)
    allow(Formula).to receive(:[]).with("shared-mime-info").and_return(formula)
    allow(Formula).to receive(:[]).with("desktop-file-utils").and_return(formula)

    runner = Homebrew::InstallSteps::Runner.new(context:)
    expect(runner).to receive(:run_command).with(root/"opt/bin/glib-compile-schemas",
                                                 HOMEBREW_PREFIX/"share/glib-2.0/schemas").ordered
    expect(runner).to receive(:run_command).with(root/"opt/bin/gio-querymodules",
                                                 HOMEBREW_PREFIX/"lib/gio/modules").ordered
    expect(runner).to receive(:run_command).with(root/"opt/bin/gdk-pixbuf-query-loaders", "--update-cache").ordered
    expect(runner).to receive(:run_command).with(root/"opt/bin/update-mime-database",
                                                 HOMEBREW_PREFIX/"share/mime").ordered
    expect(runner).to receive(:run_command).with(root/"opt/bin/update-desktop-database",
                                                 HOMEBREW_PREFIX/"share/applications").ordered

    runner.run(steps)
  end

  describe "runs gtk_update_icon_cache rebuild action" do
    let(:formula) { instance_double(Formula, opt_bin: root/"opt/bin") }
    let(:steps) do
      Homebrew::InstallSteps::DSL.build do
        gtk_update_icon_cache
      end
    end

    it "with gtk4" do
      allow(Formula).to receive(:[]).with("gtk4").and_return(formula)
      allow(Utils::Path).to receive(:formula_any_version_installed?).with("gtk4").and_return(true)
      runner = Homebrew::InstallSteps::Runner.new(context:)
      expect(runner).to receive(:run_command).with(root/"opt/bin/gtk4-update-icon-cache", "-q", "-t", "-f",
                                                   HOMEBREW_PREFIX/"share/icons/hicolor").ordered
      runner.run(steps)
    end

    it "with gtk+3" do
      allow(Formula).to receive(:[]).with("gtk+3").and_return(formula)
      allow(Utils::Path).to receive(:formula_any_version_installed?).with("gtk4").and_return(false)
      runner = Homebrew::InstallSteps::Runner.new(context:)
      expect(runner).to receive(:run_command).with(root/"opt/bin/gtk3-update-icon-cache", "-q", "-t", "-f",
                                                   HOMEBREW_PREFIX/"share/icons/hicolor").ordered
      runner.run(steps)
    end
  end

  specify "deletes matching keychain certificates by SHA-256 hash" do
    steps = Homebrew::InstallSteps::DSL.build do
      delete_keychain_certificate "Charles"
    end

    runner = Homebrew::InstallSteps::Runner.new(context:)
    expect(runner).to receive(:run_command_output)
      .with("/usr/bin/security", "find-certificate", "-a", "-c", "Charles", "-Z", sudo: true)
      .and_return(<<~EOS)
        SHA-256 hash: ABC123
        SHA-256 hash: DEF456
      EOS
    expect(runner).to receive(:run_command)
      .with("/usr/bin/security", "delete-certificate", "-Z", "ABC123", sudo: true).ordered
    expect(runner).to receive(:run_command)
      .with("/usr/bin/security", "delete-certificate", "-Z", "DEF456", sudo: true).ordered

    runner.run(steps)
  end

  specify "only deletes the keychain certificate matching a local certificate" do
    certificate = root/"home/Library/Application Support/betwixt/ssl/certs/ca.pem"
    certificate.dirname.mkpath
    certificate.write "certificate"
    steps = Homebrew::InstallSteps::DSL.build do
      delete_keychain_certificate "NodeMITMProxyCA", matching_certificate: certificate
    end

    runner = Homebrew::InstallSteps::Runner.new(context:)
    expect(runner).to receive(:run_command_output)
      .with("/usr/bin/openssl", "x509", "-fingerprint", "-sha256", "-noout", "-in", certificate)
      .and_return("sha256 Fingerprint=AB:CD:EF\n")
    expect(runner).to receive(:run_command_output)
      .with("/usr/bin/security", "find-certificate", "-a", "-c", "NodeMITMProxyCA", "-Z", sudo: true)
      .and_return(<<~EOS)
        SHA-256 hash: ABCDEF
        SHA-256 hash: FEDCBA
      EOS
    expect(runner).to receive(:run_command)
      .with("/usr/bin/security", "delete-certificate", "-Z", "ABCDEF", sudo: true)

    runner.run(steps)
  end

  specify "skips keychain certificate deletion when a local certificate is missing" do
    certificate = root/"missing.pem"
    steps = Homebrew::InstallSteps::DSL.build do
      delete_keychain_certificate "NodeMITMProxyCA", matching_certificate: certificate
    end

    runner = Homebrew::InstallSteps::Runner.new(context:)
    expect(runner).not_to receive(:run_command_output)
    expect(runner).not_to receive(:run_command)

    runner.run(steps)
  end

  specify "sets permissions and ownership for existing cask step paths" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :staged_path) do
      set_permissions ["Prepared.app", "Missing.app"], "0755"
      set_ownership "Owned.app", user: "root", group: "wheel"
    end

    command = class_double(SystemCommand)
    (root/"stage/Prepared.app").mkpath
    (root/"stage/Owned.app").mkpath

    allow(Cask::Quarantine).to receive(:app_management_permissions_granted?)
      .with(app: root/"stage/Owned.app", command:)
      .and_return(true)
    expect(command).to receive(:run!)
      .with("chmod", args: ["-R", "--", "0755", root/"stage/Prepared.app"], sudo: false).ordered
    expect(command).to receive(:run!)
      .with("chown", args: ["-R", "--", "root:wheel", root/"stage/Owned.app"], sudo: true).ordered

    Homebrew::InstallSteps::Runner.new(context:, command:).run(steps)
  end

  specify "raises when App Management permissions are missing for ownership steps" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :staged_path) do
      set_ownership "Owned.app"
    end

    command = class_double(SystemCommand)
    (root/"stage/Owned.app").mkpath

    allow(Cask::Quarantine).to receive(:app_management_permissions_granted?)
      .with(app: root/"stage/Owned.app", command:)
      .and_return(false)
    expect(command).not_to receive(:run!)

    expect { Homebrew::InstallSteps::Runner.new(context:, command:).run(steps) }
      .to raise_error(Cask::CaskError, /App Management permissions/)
  end

  specify "does not add the default base to home paths" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      mkdir_p "~/example"
    end

    expect(steps).to contain_exactly(
      "type" => "mkdir_p",
      "path" => {
        "path" => "~/example",
      },
    )
  end

  specify "moves a directory's children without moving the new target directory" do
    steps = Homebrew::InstallSteps::DSL.build(default_source_base: :staged_path, default_target_base: :staged_path) do
      move_children ".", "Nested"
    end

    (root/"stage").mkpath
    (root/"stage/source-file").write "source"

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect(root/"stage/Nested/source-file").to exist
  end

  specify "removes symlinks marked for uninstall" do
    steps = Homebrew::InstallSteps::DSL.build(default_target_base: :staged_path) do
      ln_sf "target", "linked-target", source_base: :relative, uninstall: true
    end

    (root/"stage").mkpath
    File.symlink "target", root/"stage/linked-target"

    Homebrew::InstallSteps::Runner.new(context:).run(steps, phase: :uninstall)

    expect(root/"stage/linked-target").not_to be_a_symlink
  end

  specify "does not expose the surrounding formula or cask DSL" do
    expect do
      Homebrew::InstallSteps::DSL.build(default_base: :var) do
        system "true"
      end
    end.to raise_error(NameError)
  end
end
