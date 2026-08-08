# typed: true
# frozen_string_literal: true

require "rubocops/install_steps"

RSpec.describe RuboCop::Cop::FormulaAudit::InstallSteps do
  subject(:cop) { described_class.new }

  it "only permits implemented install step methods" do
    expect(Homebrew::InstallSteps::DSL.public_instance_methods).to include(
      *(RuboCop::Cop::InstallStepsHelper::ALLOWED_STEP_METHODS |
        RuboCop::Cop::InstallStepsHelper::CASK_ALLOWED_STEP_METHODS),
    )
  end

  it "rejects `post_install` and `post_install_steps` in third-party taps" do
    expect_offense(<<~RUBY, "/Taps/example/homebrew-core/Formula/f/foo.rb")
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
        ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: `post_install` and `post_install_steps` cannot both be used.
          touch "foo/state", base: :var
        end

        def post_install; end
      end
    RUBY
  end

  it "rejects `post_install` and `post_install_steps` in official Homebrew taps" do
    expect_offense(<<~RUBY, "/Taps/homebrew/homebrew-example/Formula/f/foo.rb")
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
        ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: `post_install` and `post_install_steps` cannot both be used.
          touch "foo/state", base: :var
        end

        def post_install; end
        ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Formulae in official Homebrew taps must use `post_install_steps` instead of `post_install`.
      end
    RUBY
  end

  it "rejects coexistence regardless of component order" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install; end

        post_install_steps do
        ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: `post_install` and `post_install_steps` cannot both be used.
          touch "foo/state", base: :var
        end
      end
    RUBY
  end

  it "autocorrects implicit formula var paths" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          mkdir_p "log/foo"
          ^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Formula install-step paths must specify their base explicitly.
          write_file "foo/state", "ready"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Formula install-step paths must specify their base explicitly.
          init_data_dir "foo", using: :postgresql_initdb
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Formula install-step paths must specify their base explicitly.
          if_path_exists "foo/state" do
          ^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Formula install-step paths must specify their base explicitly.
            touch "foo/checked"
            ^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Formula install-step paths must specify their base explicitly.
          end
          run "foo", base: :bin, stdin_path: "foo/input"
                                             ^^^^^^^^^^^ FormulaAudit/InstallSteps: Formula install-step paths must specify their base explicitly.
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          mkdir_p "log/foo", base: :var
          write_file "foo/state", "ready", base: :var
          init_data_dir "foo", using: :postgresql_initdb, base: :var
          if_path_exists "foo/state", base: :var do
            touch "foo/checked", base: :var
          end
          run "foo", base: :bin, stdin_path: "{{var}}/foo/input"
        end
      end
    RUBY
  end

  it "autocorrects an empty options hash" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          touch "foo/state", {}
          ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Formula install-step paths must specify their base explicitly.
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          touch "foo/state", base: :var
        end
      end
    RUBY
  end

  it "accepts formula paths with explicit bases or absolute tokens" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          mkdir_p "log/foo", base: :var
          touch "{{var}}/foo/state"
          if_path_exists "/etc/foo.conf" do
            write_file "foo.conf", "ready", base: :etc
          end
          run "foo", base: :bin, chdir: "{{libexec}}/foo"
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
          ^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Steps blocks may only contain install step DSL calls. Prefer canonical calls: `mkdir_p`, `touch`, `move`, `move_contents`, `copy`, `remove`, `inreplace`, `symlink`, `symlink_tree`, `symlink_children`, `write_file`, `init_data_dir`, `compile_gsettings_schemas`, `update_gio_modules_cache`, `update_gdk_pixbuf_loaders_cache`, `update_gtk_icon_cache`, `update_mime_database`, `update_desktop_database`, `set_permissions`, `run`, `terminate_process`, `warn`, `change_dylib_id`, `configure_gcc_runtime`, `install_gzipped_executable`, `configure_glibc_runtime`, `configure_clang_system`, `configure_php`, `bootstrap_cpython`, `bootstrap_pypy`, `if_path_exists`, `unless_path_exists`, `on_macos`, `on_linux`.
        end
      end
    RUBY
  end

  it "rejects `brew ruby` in steps blocks" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          run "{{HOMEBREW_BREW_FILE}}", args: ["ruby", "--", "{{libexec}}/post-install.rb"]
              ^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Install steps must not use `brew ruby` because it enables developer mode.
        end
      end
    RUBY
  end

  it "accepts install step DSL calls" do
    expect_no_offenses(<<~'RUBY')
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          mkdir_p "foo", base: :var
          touch "foo/state", base: :var
          touch "foo/#{formula_name}", base: :var
          move "source", "target"
          move_contents "source", "target"
          inreplace "foo.conf", %r{{{HOMEBREW_CELLAR}}/foo/[^/]+}, "{{opt_prefix}}", base: :var,
                                                                                           audit_result: false
          symlink "source", "target", source_base: :relative, overwrite: true, remove_on_uninstall: true
          write_file "foo.conf", "key = value\n", base: :etc
          write_file "foo/adjacent", "first" "second", base: :var
          set_permissions "foo", "0755", base: :var
          run "foo", args: ["--repair"]
          terminate_process "foo", attempts: 3
          change_dylib_id "lib/libfoo.dylib", "{{opt_prefix}}/lib/libfoo.1.dylib", resolve_source: true
          if_path_exists "foo", base: :var do
            warn "foo exists"
          end
          configure_gcc_runtime
          install_gzipped_executable "compressed.gz", "bin/executable"
          configure_glibc_runtime
          configure_clang_system
          configure_php
          bootstrap_cpython
          bootstrap_pypy abi_version: "3.10"
          write_file "foo/banner", <<~TEXT, base: :var
            literal banner
          TEXT
          init_data_dir formula_name, using: :postgresql, base: :var
          symlink_tree "source", "#{formula_name}"
          symlink_children "source", suffix: "-#{version.major}"
          compile_gsettings_schemas
          update_gio_modules_cache
          update_gdk_pixbuf_loaders_cache
          update_gtk_icon_cache
          update_mime_database
          update_desktop_database
          on_macos do
            if_path_exists "foo", base: :var do
              touch "foo/scoped-state", base: :var
            end
          end
          on_linux do
            unless_path_exists "foo.conf", base: :etc do
              write_file "foo.conf", "key = value\n", base: :etc
            end
          end
        end
      end
    RUBY
  end

  it "autocorrects legacy install step names" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          mkdir "foo", base: :var
          ^^^^^ FormulaAudit/InstallSteps: Use `mkdir_p` instead of legacy install step `mkdir`.
          mv "source", "target",
          ^^ FormulaAudit/InstallSteps: Use `move` instead of legacy install step `mv`.
             force: true
             ^^^^^ FormulaAudit/InstallSteps: Use `overwrite:` instead of legacy install step keyword `force:`.
          move_children "source", "target"
          ^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Use `move_contents` instead of legacy install step `move_children`.
          ln_s "source", "target"
          ^^^^ FormulaAudit/InstallSteps: Use `symlink` instead of legacy install step `ln_s`.
          ln_sf "source", "target",
          ^^^^^ FormulaAudit/InstallSteps: Use `symlink` instead of legacy install step `ln_sf`.
                uninstall: true
                ^^^^^^^^^ FormulaAudit/InstallSteps: Use `remove_on_uninstall:` instead of legacy install step keyword `uninstall:`.
          link_dir "source", "target"
          ^^^^^^^^ FormulaAudit/InstallSteps: Use `symlink_tree` instead of legacy install step `link_dir`.
          link_children "source", "target"
          ^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Use `symlink_children` instead of legacy install step `link_children`.
          write "foo.conf", "content", base: :var
          ^^^^^ FormulaAudit/InstallSteps: Use `write_file` instead of legacy install step `write`.
          gio_querymodules
          ^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Use `update_gio_modules_cache` instead of legacy install step `gio_querymodules`.
          gdk_pixbuf_query_loaders
          ^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Use `update_gdk_pixbuf_loaders_cache` instead of legacy install step `gdk_pixbuf_query_loaders`.
          gtk_update_icon_cache
          ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Use `update_gtk_icon_cache` instead of legacy install step `gtk_update_icon_cache`.
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          mkdir_p "foo", base: :var
          move "source", "target",
             overwrite: true
          move_contents "source", "target"
          symlink "source", "target"
          symlink "source", "target",
                remove_on_uninstall: true, overwrite: true
          symlink_tree "source", "target"
          symlink_children "source", "target"
          write_file "foo.conf", "content", base: :var, overwrite: false, append_newline: true
          update_gio_modules_cache
          update_gdk_pixbuf_loaders_cache
          update_gtk_icon_cache
        end
      end
    RUBY
  end

  it "autocorrects legacy install step keywords" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          move "source", "target",
               force: true
               ^^^^^ FormulaAudit/InstallSteps: Use `overwrite:` instead of legacy install step keyword `force:`.
          symlink "source", "target",
                  force: true,
                  ^^^^^ FormulaAudit/InstallSteps: Use `overwrite:` instead of legacy install step keyword `force:`.
                  uninstall: true
                  ^^^^^^^^^ FormulaAudit/InstallSteps: Use `remove_on_uninstall:` instead of legacy install step keyword `uninstall:`.
          move "redundant", "false",
               force: false
               ^^^^^ FormulaAudit/InstallSteps: Use `overwrite:` instead of legacy install step keyword `force:`.
          move "combined", "options",
               force: true,
               ^^^^^ FormulaAudit/InstallSteps: Use `overwrite:` instead of legacy install step keyword `force:`.
               overwrite: false
          symlink "combined", "options",
                  force: true,
                  ^^^^^ FormulaAudit/InstallSteps: Use `overwrite:` instead of legacy install step keyword `force:`.
                  overwrite: false,
                  uninstall: true,
                  ^^^^^^^^^ FormulaAudit/InstallSteps: Use `remove_on_uninstall:` instead of legacy install step keyword `uninstall:`.
                  remove_on_uninstall: false
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          move "source", "target",
               overwrite: true
          symlink "source", "target",
                  overwrite: true,
                  remove_on_uninstall: true
          move "redundant", "false"
          move "combined", "options",
               overwrite: true
          symlink "combined", "options",
                  overwrite: true,
                  remove_on_uninstall: true
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
            ^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Steps blocks may only contain install step DSL calls. Prefer canonical calls: `mkdir_p`, `touch`, `move`, `move_contents`, `copy`, `remove`, `inreplace`, `symlink`, `symlink_tree`, `symlink_children`, `write_file`, `init_data_dir`, `compile_gsettings_schemas`, `update_gio_modules_cache`, `update_gdk_pixbuf_loaders_cache`, `update_gtk_icon_cache`, `update_mime_database`, `update_desktop_database`, `set_permissions`, `run`, `terminate_process`, `warn`, `change_dylib_id`, `configure_gcc_runtime`, `install_gzipped_executable`, `configure_glibc_runtime`, `configure_clang_system`, `configure_php`, `bootstrap_cpython`, `bootstrap_pypy`, `if_path_exists`, `unless_path_exists`, `on_macos`, `on_linux`.
          end
        end
      end
    RUBY
  end

  it "reports an offense when write_file content is interpolated" do
    expect_offense(<<~'RUBY')
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          write_file "foo.conf", "prefix = #{prefix}", base: :var
                                           ^^^^^^^^^ FormulaAudit/InstallSteps: Steps blocks may only contain install step DSL calls. Prefer canonical calls: `mkdir_p`, `touch`, `move`, `move_contents`, `copy`, `remove`, `inreplace`, `symlink`, `symlink_tree`, `symlink_children`, `write_file`, `init_data_dir`, `compile_gsettings_schemas`, `update_gio_modules_cache`, `update_gdk_pixbuf_loaders_cache`, `update_gtk_icon_cache`, `update_mime_database`, `update_desktop_database`, `set_permissions`, `run`, `terminate_process`, `warn`, `change_dylib_id`, `configure_gcc_runtime`, `install_gzipped_executable`, `configure_glibc_runtime`, `configure_clang_system`, `configure_php`, `bootstrap_cpython`, `bootstrap_pypy`, `if_path_exists`, `unless_path_exists`, `on_macos`, `on_linux`.
        end
      end
    RUBY
  end

  it "autocorrects simple `post_install` file preparation" do
    expect_offense(<<~RUBY, "/Taps/homebrew/homebrew-core/Formula/f/foo.rb")
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
          mkdir_p "log/foo", base: :var
          touch "foo/state", base: :var
          move "move-source", "move-target"
          symlink "move-target", "linked-target", source_base: :relative, overwrite: true
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
          write_file "foo/foo.conf", "key = value\n", base: :etc
          write_file "foo/banner", <<~TEXT, base: :var
            literal banner
          TEXT
        end
      end
    RUBY
  end

  it "autocorrects config writes without trailing newlines" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
        ^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Use `post_install_steps` for simple file preparation.
          (var/"foo.conf").write "key = value"
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          write_file "foo.conf", "key = value", base: :var
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
          update_gdk_pixbuf_loaders_cache
          update_gtk_icon_cache
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
        ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: `post_install` and `post_install_steps` cannot both be used.
          touch "postgresql/state", base: :var
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

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          touch "postgresql/state", base: :var
          mkdir_p "log", base: :var
          symlink_tree "include/postgresql", "include/{{formula_name}}"
          symlink_tree "lib/postgresql", "lib/{{formula_name}}"
          symlink_tree "share/postgresql", "share/{{formula_name}}"
          symlink_children "bin", suffix: "-{{version.major}}"
          init_data_dir formula_name, using: :postgresql, base: :var
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
          init_data_dir "mysql", using: :mysql, base: :var
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
          init_data_dir "mysql", using: :mariadb, base: :var
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
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          symlink_tree "include/postgresql", "include/{{formula_name}}"
          symlink_children "bin", suffix: "-{{version.major}}"
          init_data_dir formula_name, using: :postgresql, base: :var
          symlink "cert.pem", "cert.pem",
                  source_formula: "ca-certificates",
                  source_base:    :formula_pkgetc,
                  target_base:    :pkgetc,
                  overwrite:      true
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
                  overwrite: true
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
          mkdir_p "run/foo", base: :var
          mkdir_p "log/foo", base: :var
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
          mkdir_p "run/foo", base: :var
          mkdir_p "state/foo", base: :var
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
          mkdir_p "run", base: :var
        end

        service do
          run [opt_bin/"foo", "-s", var/"run/foo.sock"]
        end
      end
    RUBY
  end
end
