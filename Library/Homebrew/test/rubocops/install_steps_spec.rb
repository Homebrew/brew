# typed: true
# frozen_string_literal: true

require "rubocops/install_steps"

RSpec.describe RuboCop::Cop::FormulaAudit::InstallSteps do
  subject(:cop) { described_class.new }

  it "allows `post_install` and `post_install_steps` during incremental conversion" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          touch "foo/state"
        end

        def post_install; end
      end
    RUBY
  end

  it "reports an offense when `post_install_steps` appears after `post_install`" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install; end

        post_install_steps do
        ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: `post_install_steps` must appear before `post_install` to match run order.
          touch "foo/state"
        end
      end
    RUBY
  end

  it "reports an offense when a steps block contains Ruby code" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          system "true"
          ^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Steps blocks may only contain install step DSL calls: `mkdir`, `mkdir_p`, `touch`, `move`, `mv`, `move_children`, `move_contents`, `copy`, `remove`, `inreplace`, `symlink`, `ln_s`, `ln_sf`, `link_dir`, `link_children`, `write`, `init_data_dir`, `compile_gsettings_schemas`, `gio_querymodules`, `gdk_pixbuf_query_loaders`, `gtk_update_icon_cache`, `update_mime_database`, `update_desktop_database`, `if_path_exists`, `unless_path_exists`, `on_macos`, `on_linux`.
        end
      end
    RUBY
  end

  it "accepts install step DSL calls" do
    expect_no_offenses(<<~'RUBY')
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          mkdir_p "foo"
          touch "foo/state"
          touch "foo/#{formula_name}"
          mv "source", "target"
          move_children "source", "target"
          move_contents "source", "target"
          inreplace "foo.conf", /@PREFIX@/, "{{HOMEBREW_PREFIX}}"
          ln_sf "source", "target", source_base: :relative, uninstall: true
          write "foo.conf", "key = value\n", base: :etc
          write "foo/banner", <<~TEXT
            literal banner
          TEXT
          init_data_dir name, using: :postgresql_initdb
          link_dir "source", "#{name}"
          link_children "source", suffix: "-#{version.major}"
          compile_gsettings_schemas
          gio_querymodules
          gdk_pixbuf_query_loaders
          gtk_update_icon_cache
          update_mime_database
          update_desktop_database
          on_macos do
            if_path_exists "foo" do
              touch "foo/scoped-state"
            end
          end
          on_linux do
            unless_path_exists "foo.conf", base: :etc do
              write "foo.conf", "key = value\n", base: :etc
            end
          end
        end
      end
    RUBY
  end

  it "reports an offense when a scope contains Ruby code" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          on_macos do
            system "true"
            ^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Steps blocks may only contain install step DSL calls: `mkdir`, `mkdir_p`, `touch`, `move`, `mv`, `move_children`, `move_contents`, `copy`, `remove`, `inreplace`, `symlink`, `ln_s`, `ln_sf`, `link_dir`, `link_children`, `write`, `init_data_dir`, `compile_gsettings_schemas`, `gio_querymodules`, `gdk_pixbuf_query_loaders`, `gtk_update_icon_cache`, `update_mime_database`, `update_desktop_database`, `if_path_exists`, `unless_path_exists`, `on_macos`, `on_linux`.
          end
        end
      end
    RUBY
  end

  it "reports an offense when write content is interpolated" do
    expect_offense(<<~'RUBY')
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          write "foo.conf", "prefix = #{prefix}"
                                      ^^^^^^^^^ FormulaAudit/InstallSteps: Steps blocks may only contain install step DSL calls: `mkdir`, `mkdir_p`, `touch`, `move`, `mv`, `move_children`, `move_contents`, `copy`, `remove`, `inreplace`, `symlink`, `ln_s`, `ln_sf`, `link_dir`, `link_children`, `write`, `init_data_dir`, `compile_gsettings_schemas`, `gio_querymodules`, `gdk_pixbuf_query_loaders`, `gtk_update_icon_cache`, `update_mime_database`, `update_desktop_database`, `if_path_exists`, `unless_path_exists`, `on_macos`, `on_linux`.
        end
      end
    RUBY
  end

  it "autocorrects simple `post_install` file preparation" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
        ^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Use `post_install_steps` for simple file preparation.
          (var/"log/foo").mkpath
          FileUtils.touch var/"foo/state"
          FileUtils.mv prefix/"move-source", prefix/"move-target"
          FileUtils.ln_sf "move-target", prefix/"linked-target"
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          mkdir_p "log/foo"
          touch "foo/state"
          mv "move-source", "move-target"
          ln_sf "move-target", "linked-target", source_base: :relative
        end
      end
    RUBY
  end

  it "autocorrects simple `post_install` config writes" do
    expect_offense(<<~'RUBY')
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
        ^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Use `post_install_steps` for simple file preparation.
          (etc/"foo/foo.conf").write "key = value\n"
          (var/"foo/banner").atomic_write <<~TEXT
            literal banner
          TEXT
        end
      end
    RUBY

    expect_correction(<<~'RUBY')
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          write "foo/foo.conf", "key = value\n", base: :etc, overwrite: true
          write "foo/banner", <<~TEXT, overwrite: true
            literal banner
          TEXT
        end
      end
    RUBY
  end

  it "does not autocorrect config writes without trailing newlines" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
          (var/"foo.conf").write "key = value"
        end
      end
    RUBY
  end

  it "autocorrects known `post_install` rebuild actions" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
        ^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Use `post_install_steps` for simple file preparation.
          system Formula["glib"].opt_bin/"glib-compile-schemas", HOMEBREW_PREFIX/"share/glib-2.0/schemas"
          system Formula["glib"].opt_bin/"gio-querymodules", HOMEBREW_PREFIX/"lib/gio/modules"
          system Formula["gdk-pixbuf"].opt_bin/"gdk-pixbuf-query-loaders", "--update-cache"
          system Formula["gtk+3"].opt_bin/"gtk3-update-icon-cache", "-q", "-t", "-f", HOMEBREW_PREFIX/"share/icons/hicolor"
          system Formula["shared-mime-info"].opt_bin/"update-mime-database", HOMEBREW_PREFIX/"share/mime"
          system Formula["desktop-file-utils"].opt_bin/"update-desktop-database", HOMEBREW_PREFIX/"share/applications"
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          compile_gsettings_schemas
          gio_querymodules
          gdk_pixbuf_query_loaders
          gtk_update_icon_cache
          update_mime_database
          update_desktop_database
        end
      end
    RUBY
  end

  it "autocorrects PostgreSQL bootstrap and link sequences into existing steps" do
    expect_offense(<<~'RUBY')
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          touch "postgresql/state"
        end

        def post_install
        ^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Use `post_install_steps` for simple file preparation.
          (var/"log").mkpath
          postgresql_datadir.mkpath

          %w[include lib share].each do |dir|
            dst_dir = HOMEBREW_PREFIX/dir/name
            src_dir = prefix/dir/"postgresql"
            src_dir.find do |src|
              dst = dst_dir/src.relative_path_from(src_dir)
              next if dst.directory? && !dst.symlink? && src.directory? && !src.symlink?

              rm_r(dst) if dst.exist? || dst.symlink?
              if src.symlink? || src.file?
                Find.prune if src.basename.to_s == ".DS_Store"
                dst.parent.install_symlink src
              elsif src.directory?
                dst.mkpath
              end
            end
          end

          bin.each_child { |f| (HOMEBREW_PREFIX/"bin").install_symlink f => "#{f.basename}-#{version.major}" }
          return if ENV["HOMEBREW_GITHUB_ACTIONS"]

          system bin/"initdb", "--locale=en_US.UTF-8", "-E", "UTF-8", postgresql_datadir unless pg_version_exists?
          opoo "keep this legacy work"
        end

        def postgresql_datadir
          var/name
        end

        def pg_version_exists?
          (postgresql_datadir/"PG_VERSION").exist?
        end
      end
    RUBY

    expect_correction(<<~'RUBY')
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          touch "postgresql/state"
          mkdir_p "log"
          link_dir "include/postgresql", "include/#{name}"
          link_dir "lib/postgresql", "lib/#{name}"
          link_dir "share/postgresql", "share/#{name}"
          link_children "bin", suffix: "-#{version.major}"
          init_data_dir name, using: :postgresql_initdb
        end

        def post_install
          opoo "keep this legacy work"
        end

        def postgresql_datadir
          var/name
        end
      end
    RUBY
  end

  it "autocorrects MySQL bootstrap while retaining its warning" do
    expect_offense(<<~'RUBY')
      class Mysql < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
        ^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Use `post_install_steps` for simple file preparation.
          (var/"mysql").mkpath

          if File.exist? "/etc/my.cnf"
            opoo "existing configuration"
          end

          return if ENV["HOMEBREW_GITHUB_ACTIONS"]

          unless (datadir/"mysql/general_log.CSM").exist?
            ENV["TMPDIR"] = nil
            system bin/"mysqld", "--initialize-insecure", "--user=#{ENV["USER"]}",
                                 "--basedir=#{prefix}", "--datadir=#{datadir}", "--tmpdir=/tmp"
          end
        end

        def datadir
          var/"mysql"
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Mysql < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          init_data_dir "mysql", using: :mysql_initialize
        end

        def post_install
          if File.exist? "/etc/my.cnf"
            opoo "existing configuration"
          end
        end

        def datadir
          var/"mysql"
        end
      end
    RUBY
  end

  it "autocorrects MariaDB bootstrap-only hooks" do
    expect_offense(<<~'RUBY')
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
        ^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Use `post_install_steps` for simple file preparation.
          (var/"mysql").mkpath
          return if ENV["HOMEBREW_GITHUB_ACTIONS"]

          unless File.exist? "#{var}/mysql/mysql/user.frm"
            ENV["TMPDIR"] = nil
            system bin/"mysql_install_db", "--verbose", "--user=#{ENV["USER"]}",
              "--basedir=#{prefix}", "--datadir=#{var}/mysql", "--tmpdir=/tmp"
          end
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          init_data_dir "mysql", using: :mariadb_install_db
        end
      end
    RUBY
  end

  it "does not autocorrect dynamic or unsupported database and link work" do
    expect_no_offenses(<<~'RUBY')
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
          return if ENV["HOMEBREW_GITHUB_ACTIONS"]
          system bin/"initdb", "--locale=#{ENV.fetch("LC_ALL")}", "-E", "UTF-8", postgresql_datadir
        end
      end
    RUBY

    expect_no_offenses(<<~'RUBY')
      class PerconaServer < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
          (var/"mysql").mkpath
          return if ENV["HOMEBREW_GITHUB_ACTIONS"]

          unless (datadir/"mysql/general_log.CSM").exist?
            ENV["TMPDIR"] = nil
            system bin/"mysqld", "--initialize-insecure", "--user=#{ENV["USER"]}",
                                 "--basedir=#{prefix}", "--datadir=#{datadir}", "--tmpdir=/tmp"
          end
        end

        def datadir
          var/"mysql"
        end
      end
    RUBY

    expect_no_offenses(<<~RUBY)
      class Mysql < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
          (var/"mysql").mkpath
          return if ENV["HOMEBREW_GITHUB_ACTIONS"]
          system bin/"mysqld", "--initialize-insecure", "--skip-grant-tables"
        end
      end
    RUBY

    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
          lib.each_child { |child| dynamic_target.install_symlink child }
        end
      end
    RUBY
  end

  it "does not re-report declarative database and link steps" do
    expect_no_offenses(<<~'RUBY')
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          link_dir "include/postgresql", "include/#{name}"
          link_children "bin", suffix: "-#{version.major}"
          init_data_dir name, using: :postgresql_initdb
          symlink "cert.pem", "cert.pem",
                  source_formula: "ca-certificates",
                  source_base:    :formula_pkgetc,
                  target_base:    :pkgetc,
                  force:          true
        end
      end
    RUBY
  end

  it "autocorrects direct certificate bundle symlinks while retaining legacy work" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
        ^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Use `post_install_steps` for simple file preparation.
          rm(pkgetc/"cert.pem") if (pkgetc/"cert.pem").exist?
          pkgetc.install_symlink Formula["ca-certificates"].pkgetc/"cert.pem"
          opoo "keep this legacy work"
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          symlink "cert.pem", "cert.pem",
                  source_formula: "ca-certificates",
                  source_base: :formula_pkgetc,
                  target_base: :pkgetc,
                  force: true
        end

        def post_install
          opoo "keep this legacy work"
        end
      end
    RUBY
  end

  it "does not autocorrect dynamic or unsupported certificate symlinks" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
          rm(openssldir/"cert.pem") if (openssldir/"cert.pem").exist?
          openssldir.install_symlink Formula["ca-certificates"].pkgetc/"cert.pem"
        end
      end
    RUBY

    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
          rm(pkgetc/"cert.pem") if (pkgetc/"cert.pem").exist?
          pkgetc.install_symlink Formula["custom-ca"].pkgetc/"cert.pem"
        end
      end
    RUBY
  end

  it "does not autocorrect non-file preparation in `post_install`" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
          system "true"
        end
      end
    RUBY
  end

  it "does not autocorrect mixed `post_install` bodies" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
          (var/"log/foo").mkpath
          system "true"
        end
      end
    RUBY
  end

  it "autocorrects redundant service path directories in `post_install`" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
        ^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: `post_install` only creates directories created by `brew services`.
          (var/"run/foo").mkpath
          (var/"log/foo").mkpath
        end

        service do
          run opt_bin/"foo"
          working_dir var/"run/foo"
          log_path var/"log/foo/out.log"
          error_log_path var/"log/foo/err.log"
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        service do
          run opt_bin/"foo"
          working_dir var/"run/foo"
          log_path var/"log/foo/out.log"
          error_log_path var/"log/foo/err.log"
        end
      end
    RUBY
  end

  it "autocorrects redundant service path directories in `post_install_steps`" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
        ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: `post_install_steps` only creates directories created by `brew services`.
          mkdir_p "run/foo"
          mkdir_p "log/foo"
        end

        service do
          run opt_bin/"foo"
          working_dir var/"run/foo"
          log_path var/"log/foo/out.log"
          error_log_path var/"log/foo/err.log"
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        service do
          run opt_bin/"foo"
          working_dir var/"run/foo"
          log_path var/"log/foo/out.log"
          error_log_path var/"log/foo/err.log"
        end
      end
    RUBY
  end

  it "does not report mixed `post_install_steps` bodies" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          mkdir_p "run/foo"
          mkdir_p "state/foo"
        end

        service do
          run opt_bin/"foo"
          working_dir var/"run/foo"
        end
      end
    RUBY
  end

  it "does not use runtime arguments as service path directories" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          mkdir_p "run"
        end

        service do
          run [opt_bin/"foo", "-s", var/"run/foo.sock"]
        end
      end
    RUBY
  end
end
