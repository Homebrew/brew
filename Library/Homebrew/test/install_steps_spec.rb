# typed: false
# frozen_string_literal: true

require "install_steps"

RSpec.describe Homebrew::InstallSteps do
  let(:root) { Pathname(TEST_TMPDIR)/"install-steps" }
  let(:context) do
    root_path = root
    Class.new do
      define_method(:prefix) { root_path/"prefix" }
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
    ]

    expect(Homebrew::InstallSteps::DSL.normalise_steps(steps)).to contain_exactly(
      "type" => "mkdir_p",
      "path" => {
        "base" => "var",
        "path" => "nested/example",
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

  specify "runs named desktop and cache rebuild actions" do
    steps = Homebrew::InstallSteps::DSL.build do
      compile_gsettings_schemas
      gio_querymodules
      gdk_pixbuf_query_loaders
      gtk_update_icon_cache
      update_mime_database
      update_desktop_database
    end

    formula = instance_double(Formula, opt_bin: root/"opt/bin")
    allow(Formula).to receive(:[]).with("glib").and_return(formula)
    allow(Formula).to receive(:[]).with("gdk-pixbuf").and_return(formula)
    allow(Formula).to receive(:[]).with("gtk+3").and_return(formula)
    allow(Formula).to receive(:[]).with("shared-mime-info").and_return(formula)
    allow(Formula).to receive(:[]).with("desktop-file-utils").and_return(formula)
    expect(context).to receive(:safe_system).with(root/"opt/bin/glib-compile-schemas",
                                                  HOMEBREW_PREFIX/"share/glib-2.0/schemas").ordered
    expect(context).to receive(:safe_system).with(root/"opt/bin/gio-querymodules",
                                                  HOMEBREW_PREFIX/"lib/gio/modules").ordered
    expect(context).to receive(:safe_system).with(root/"opt/bin/gdk-pixbuf-query-loaders", "--update-cache").ordered
    expect(context).to receive(:safe_system).with(root/"opt/bin/gtk3-update-icon-cache", "-q", "-t", "-f",
                                                  HOMEBREW_PREFIX/"share/icons/hicolor").ordered
    expect(context).to receive(:safe_system).with(root/"opt/bin/update-mime-database",
                                                  HOMEBREW_PREFIX/"share/mime").ordered
    expect(context).to receive(:safe_system).with(root/"opt/bin/update-desktop-database",
                                                  HOMEBREW_PREFIX/"share/applications").ordered

    Homebrew::InstallSteps::Runner.new(context:).run(steps)
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
