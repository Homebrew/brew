# typed: true
# frozen_string_literal: true

require "rubocops/install_steps"

RSpec.describe RuboCop::Cop::FormulaAudit::InstallSteps do
  subject(:cop) { described_class.new }

  it "reports an offense when `post_install` and `post_install_steps` are both present" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
        ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: `post_install` and `post_install_steps` cannot both be used.
          touch "foo/state"
        end

        def post_install; end
      end
    RUBY
  end

  it "reports an offense when a steps block contains Ruby code" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          system "true"
          ^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Steps blocks may only contain install step DSL calls: `mkdir`, `mkdir_p`, `touch`, `move`, `mv`, `move_children`, `symlink`, `ln_s`, `ln_sf`, `write`, `compile_gsettings_schemas`, `gio_querymodules`, `gdk_pixbuf_query_loaders`, `gtk_update_icon_cache`, `update_mime_database`, `update_desktop_database`.
        end
      end
    RUBY
  end

  it "accepts install step DSL calls" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          mkdir_p "foo"
          touch "foo/state"
          mv "source", "target"
          move_children "source", "target"
          ln_sf "source", "target", source_base: :relative, uninstall: true
          write "foo.conf", "key = value\n", base: :etc
          write "foo/banner", <<~TEXT
            literal banner
          TEXT
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

  it "reports an offense when write content is interpolated" do
    expect_offense(<<~'RUBY')
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          write "foo.conf", "prefix = #{prefix}"
                                      ^^^^^^^^^ FormulaAudit/InstallSteps: Steps blocks may only contain install step DSL calls: `mkdir`, `mkdir_p`, `touch`, `move`, `mv`, `move_children`, `symlink`, `ln_s`, `ln_sf`, `write`, `compile_gsettings_schemas`, `gio_querymodules`, `gdk_pixbuf_query_loaders`, `gtk_update_icon_cache`, `update_mime_database`, `update_desktop_database`.
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
