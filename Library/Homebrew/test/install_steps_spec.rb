# typed: true
# frozen_string_literal: true

require "install_steps"
require "api/formula_struct"
require "cask/quarantine"
require "formulary"
require "macho"

RSpec.describe Homebrew::InstallSteps do
  let(:root) { Pathname(TEST_TMPDIR)/"install-steps" }
  let(:context) do
    root_path = root
    Class.new do
      define_method(:prefix) { root_path/"prefix" }
      define_method(:bin) { root_path/"prefix/bin" }
      define_method(:libexec) { root_path/"prefix/libexec" }
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

  around do |example|
    with_env(HOMEBREW_GITHUB_ACTIONS: nil) do
      example.run
    end
  end

  def api_formula(name, version)
    formula_struct = Homebrew::API::FormulaStruct.from_hash({
      "desc"                 => "API formula",
      "homepage"             => "https://example.com",
      "license"              => "MIT",
      "ruby_source_checksum" => "checksum",
      "stable_present"       => true,
      "stable_url_args"      => ["https://example.com/#{name}-#{version}.tar.gz", {}],
      "stable_version"       => version,
    })
    api_source = formula_struct.serialize
    formula_class = Formulary.load_formula_from_struct!(
      name,
      Homebrew::API::FormulaStruct.deserialize(api_source),
      api_source:,
      tap_git_head: "",
      flags:        [],
      internal_api: true,
    )
    formula_class.new(name, root/"#{name}.rb", :stable)
  end

  def create_executable(path)
    path.dirname.mkpath
    path.write ""
    path.chmod 0755
  end

  specify "changes the resolved dylib ID and restores its mode" do
    dylib = root/"lib/libfoo.1.dylib"
    source = root/"lib/libfoo.dylib"
    dylib.dirname.mkpath
    dylib.write "Mach-O"
    dylib.chmod 0444
    FileUtils.ln_s dylib, source
    allow(Hardware::CPU).to receive(:arm?).and_return(true)
    expect(MachO::Tools).to receive(:change_dylib_id).with(dylib, "@rpath/libfoo.1.dylib")
    expect(MachO).to receive(:codesign!).with(dylib)

    described_class.change_dylib_id source, "@rpath/libfoo.1.dylib", resolve_source: true

    expect(dylib.stat.mode & 0777).to eq(0444)
  end

  specify "runs directory, touch, move and symlink steps", :aggregate_failures do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var, default_source_base: :staged_path,
                                              default_target_base: :staged_path) do
      mkdir_p "log/example"
      touch "state/marker", base: :prefix
      move "move-source", "move-target"
      symlink "move-target", "linked-target", source_base: :relative
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

  specify "allows directory creation through parent sandbox paths" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :prefix) do
      mkdir "one"
      mkdir_p "two/three"
    end

    paths = Homebrew::InstallSteps::Runner.new(context:).sandbox_write_paths(steps)

    expect(paths).to contain_exactly(root/"prefix", root/"prefix/two")
  end

  specify "resolves formula configuration paths without loading formula source" do
    stub_const("HOMEBREW_PREFIX", root/"homebrew")
    source = HOMEBREW_PREFIX/"etc/test-source/cert.pem"
    source.dirname.mkpath
    source.write "certificate"
    steps = Homebrew::InstallSteps::DSL.build(default_target_base: :prefix) do
      symlink "cert.pem", "cert.pem", source_base:    :formula_pkgetc,
                                      source_formula: "example/tap/test-source"
    end

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect(root/"prefix/cert.pem").to be_a_symlink
  end

  specify "changes an explicit Mach-O dylib ID" do
    steps = Homebrew::InstallSteps::DSL.build(default_source_base: :prefix) do
      on_macos do
        change_dylib_id "lib/libfoo.dylib", "{{HOMEBREW_PREFIX}}/opt/foo/lib/libfoo.1.dylib",
                        resolve_source: true
      end
    end
    allow(Homebrew::SimulateSystem).to receive(:simulating_or_running_on_macos?).and_return(true)
    expect(described_class).to receive(:change_dylib_id)
      .with(root/"prefix/lib/libfoo.dylib", "#{HOMEBREW_PREFIX}/opt/foo/lib/libfoo.1.dylib", resolve_source: true)

    Homebrew::InstallSteps::Runner.new(context:).run(steps)
  end

  specify "links every source matched by a glob into a directory", :aggregate_failures do
    steps = Homebrew::InstallSteps::DSL.build(default_source_base: :prefix,
                                              default_target_base: :prefix) do
      symlink "share/man/*.1", "share/man/man1", source_glob: true, overwrite: true
    end

    (root/"prefix/share/man/man1").mkpath
    (root/"prefix/share/man/tool.1").write "tool"
    (root/"prefix/share/man/other.1").write "other"

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect(root/"prefix/share/man/man1/tool.1").to be_a_symlink
    expect(root/"prefix/share/man/man1/other.1").to be_a_symlink
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

  specify "keeps canonical DSL calls compatible with shipped API values", :aggregate_failures do
    steps = Homebrew::InstallSteps::DSL.build do
      symlink_tree "source", "target"
      symlink_children "source", "target"
      write_file "config", "content"
      update_gdk_pixbuf_loaders_cache
      update_gtk_icon_cache
      delete_keychain_certificates "Example", fingerprint_of: "certificate"
      symlink "source", "target", overwrite: true, remove_on_uninstall: true
      init_data_dir "data", using: :postgresql
    end

    expect(steps.map { |step| step.fetch("type") }).to eq(
      %w[link_dir link_children write gdk_pixbuf_query_loaders gtk_update_icon_cache
         delete_keychain_certificate symlink init_data_dir],
    )
    expect(steps.fetch(2)).to include("content" => "content", "overwrite" => true)
    expect(steps.fetch(5)).to include("matching_certificate" => { "path" => "certificate" })
    expect(steps.fetch(6)).to include("force" => true, "uninstall" => true)
    expect(steps.fetch(7)).to include("using" => "postgresql_initdb")
  end

  specify "keeps shipped step names serialisable for compatibility" do
    steps = Homebrew::InstallSteps::DSL.build do
      mkdir "directory"
      mv "source", "target"
      move_children "source", "target"
      ln_sf "source", "target"
      link_dir "source", "target"
      link_children "source", "target"
      write "config", "content"
      gio_querymodules
      gdk_pixbuf_query_loaders
      gtk_update_icon_cache
      delete_keychain_certificate "Example"
    end

    expect(steps.map { |step| step.fetch("type") }).to eq(%w[
      mkdir move move_children symlink link_dir link_children write gio_querymodules
      gdk_pixbuf_query_loaders gtk_update_icon_cache delete_keychain_certificate
    ])
  end

  specify "expands a scoped set of content tokens and leaves others verbatim", :aggregate_failures do
    root_path = root
    versioned_context = Class.new do
      define_method(:prefix) { root_path/"prefix" }
      define_method(:name) { "example" }
      define_method(:token) { "example-cask" }
      define_method(:version) { Version.new("1.2.3") }
    end.new

    steps = Homebrew::InstallSteps::DSL.build(default_base: :prefix) do
      write_file "config.ini", <<~EOS
        prefix = {{prefix}}
        cellar = {{HOMEBREW_PREFIX}}
        legacy = {{name}}
        formula = {{formula_name}}
        cask = {{token}}
        series = {{version.major_minor}} ({{version}})
        literal = {{unknown}} {single}
      EOS
    end

    Homebrew::InstallSteps::Runner.new(context: versioned_context).run(steps)

    written = (root/"prefix/config.ini").read
    expect(written).to include("prefix = #{root}/prefix")
    expect(written).to include("cellar = #{HOMEBREW_PREFIX}")
    expect(written).to include("legacy = example")
    expect(written).to include("formula = example")
    expect(written).to include("cask = example-cask")
    expect(written).to include("series = 1.2 (1.2.3)")
    expect(written).to include("literal = {{unknown}} {single}")
  end

  specify "expands formula and cask identity tokens" do
    context.define_singleton_method(:name) { "example-formula" }
    context.define_singleton_method(:token) { "example-cask" }
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      write "identity", "#{formula_name}:#{token}"
    end

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect((root/"var/identity").read).to eq("example-formula:example-cask\n")
  end

  specify "writes exact content and replaces existing files" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      write_file "config/example.conf", "replacement"
      write_file "empty", ""
    end

    (root/"var/config").mkpath
    (root/"var/config/example.conf").write "old\n"

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect([(root/"var/config/example.conf").read, (root/"var/empty").read]).to eq(["replacement", ""])
  end

  specify "can append a newline without replacing existing files" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      write_file "existing", "replacement", overwrite: false, append_newline: true
      write_file "missing", "new", overwrite: false, append_newline: true
    end

    (root/"var").mkpath
    (root/"var/existing").write "original\n"

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect([(root/"var/existing").read, (root/"var/missing").read]).to eq(["original\n", "new\n"])
  end

  specify "preserves meaningful blank values" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      inreplace "remove.txt", "remove", ""
      run "helper", args: [""], env: { "EMPTY" => "" }
    end

    (root/"var").mkpath
    (root/"var/remove.txt").write "remove"
    command = class_double(SystemCommand)
    expect(command).to receive(:run!)
      .with("helper", args: [""], sudo: false, env: { "EMPTY" => "" }, input: [], print_stdout: false,
                      print_stderr: true, reset_uid: true, chdir: nil)

    Homebrew::InstallSteps::Runner.new(context:, command:).run(steps)

    expect((root/"var/remove.txt").read).to be_empty
  end

  specify "omits install step runtime defaults" do
    steps = Homebrew::InstallSteps::DSL.build(default_base:        :staged_path,
                                              default_source_base: :staged_path,
                                              default_target_base: :staged_path) do
      copy "source", "target"
      symlink "source", "target"
      write "config", "content"
      set_ownership "Example.app"
      terminate_process "Example"
    end

    expect(steps).to all(satisfy do |step|
      !step.keys.intersect?(%w[attempts force group match overwrite uninstall])
    end)
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

  specify "snapshots conditions shared by a scope" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      unless_path_exists "initialised" do
        mkdir_p "initialised"
        touch "initialised/marker"
      end
    end

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect(root/"var/initialised/marker").to exist
  end

  specify "keeps guard snapshots separate between concatenated step lists" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      if_path_exists "missing" do
        touch "unexpected"
      end
    end
    steps.concat(
      Homebrew::InstallSteps::DSL.build(default_base: :var) do
        if_path_exists "existing" do
          touch "matched"
        end
      end,
    )
    (root/"var/existing").mkpath

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect(root/"var/matched").to exist
  end

  specify "runs only steps matching the simulated platform" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      on_macos do
        touch "macos"
      end
      on_linux do
        touch "linux"
      end
    end

    expect([:macos, :linux].to_h do |os|
      FileUtils.rm_rf root/"var"
      Homebrew::SimulateSystem.with(os:) do
        Homebrew::InstallSteps::Runner.new(context:).run(steps)
      end
      [os, [(root/"var/macos").exist?, (root/"var/linux").exist?]]
    end).to eq(macos: [true, false], linux: [false, true])
  end

  specify "copies paths" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var, default_source_base: :staged_path,
                                              default_target_base: :var) do
      copy "source.txt", "copied.txt"
    end

    (root/"stage").mkpath
    (root/"stage/source.txt").write "copied"

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect((root/"var/copied.txt").read).to eq("copied")
  end

  specify "replaces copied paths by default and can reject replacement" do
    rejecting_steps = Homebrew::InstallSteps::DSL.build(default_source_base: :staged_path,
                                                        default_target_base: :var) do
      copy "source.txt", "copied.txt", overwrite: false
    end
    steps = Homebrew::InstallSteps::DSL.build(default_source_base: :staged_path, default_target_base: :var) do
      copy "source.txt", "copied.txt"
    end
    (root/"stage").mkpath
    (root/"var").mkpath
    (root/"stage/source.txt").write "replacement"
    (root/"var/copied.txt").write "existing"

    expect { Homebrew::InstallSteps::Runner.new(context:).run(rejecting_steps) }.to raise_error(Errno::EEXIST)

    Homebrew::InstallSteps::Runner.new(context:).run(steps)
    expect((root/"var/copied.txt").read).to eq("replacement")
  end

  specify "replaces symlink destinations when copying files" do
    steps = Homebrew::InstallSteps::DSL.build(default_source_base: :staged_path, default_target_base: :var) do
      copy "source.txt", "copied.txt"
    end
    (root/"stage").mkpath
    (root/"var").mkpath
    (root/"stage/source.txt").write "replacement"
    (root/"var/linked.txt").write "original"
    File.symlink "linked.txt", root/"var/copied.txt"

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect([(root/"var/copied.txt").symlink?, (root/"var/copied.txt").read, (root/"var/linked.txt").read])
      .to eq([false, "replacement", "original"])
  end

  specify "preserves the legacy move replacement behaviour" do
    steps = Homebrew::InstallSteps::DSL.build(default_source_base: :staged_path, default_target_base: :var) do
      move "source.txt", "target.txt"
    end
    (root/"stage").mkpath
    (root/"var").mkpath
    (root/"stage/source.txt").write "replacement"
    (root/"var/target.txt").write "existing"

    steps.fetch(0).delete("overwrite")
    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect((root/"var/target.txt").read).to eq("replacement")
  end

  specify "preserves a default move destination when repeated", :aggregate_failures do
    steps = Homebrew::InstallSteps::DSL.build(default_source_base: :staged_path, default_target_base: :var) do
      move "source", "target"
    end
    (root/"stage/source").mkpath
    (root/"stage/source/file").write "content"
    runner = Homebrew::InstallSteps::Runner.new(context:)

    runner.run(steps)
    expect { runner.run(steps) }.to raise_error(Errno::ENOENT)
    expect((root/"var/target/file").read).to eq("content")
  end

  specify "requires one match for single-source globs" do
    steps = Homebrew::InstallSteps::DSL.build(default_source_base: :staged_path, default_target_base: :var) do
      copy "*.txt", "copied.txt", source_glob: true
    end
    (root/"stage").mkpath
    (root/"stage/first.txt").write "first"
    (root/"stage/second.txt").write "second"

    expect { Homebrew::InstallSteps::Runner.new(context:).run(steps) }
      .to raise_error(ArgumentError, /exactly one path/)
  end

  specify "requires a match for literal glob sources" do
    steps = Homebrew::InstallSteps::DSL.build(default_source_base: :staged_path, default_target_base: :var) do
      copy "missing.txt", "copied.txt", source_glob: true
    end

    expect { Homebrew::InstallSteps::Runner.new(context:).run(steps) }
      .to raise_error(ArgumentError, /exactly one path/)
  end

  specify "deduplicates overlapping move source globs" do
    steps = Homebrew::InstallSteps::DSL.build(default_source_base: :staged_path,
                                              default_target_base: :staged_path) do
      move "{WezTerm-*,WezTerm-*}/WezTerm.app", ".", source_glob: true
    end
    (root/"stage/WezTerm-nightly/WezTerm.app").mkpath

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect(root/"stage/WezTerm.app").to be_a_directory
  end

  specify "removes paths and expands globs", :aggregate_failures do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      remove ["obsolete.txt", "obsolete-*"], recursive: true
    end

    (root/"var/obsolete-dir").mkpath
    (root/"var/obsolete.txt").write "obsolete"
    (root/"var/obsolete-dir/child").write "obsolete"

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect(root/"var/obsolete.txt").not_to exist
    expect(root/"var/obsolete-dir").not_to exist
  end

  specify "filters removals and accepts the legacy path base", :aggregate_failures do
    ENV["PATH"] = (root/"path-bin").to_s
    steps = Homebrew::InstallSteps::DSL.build do
      remove "links/*", base: :staged_path, symlink_target_contains: "wanted"
      remove "launcher", base: :path, content_contains: "owned marker"
    end

    (root/"stage/links").mkpath
    (root/"stage/links/wanted").make_symlink("/tmp/wanted-target")
    (root/"stage/links/kept").make_symlink("/tmp/other-target")
    (root/"path-bin").mkpath
    (root/"path-bin/launcher").write "owned marker"

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect(root/"stage/links/wanted").not_to exist
    expect(root/"stage/links/kept").to be_a_symlink
    expect(root/"path-bin/launcher").not_to exist
  end

  specify "uses elevated cask removal when requested" do
    require "cask/utils"

    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      remove "protected", sudo: true
    end
    (root/"var/protected").mkpath
    command = class_double(SystemCommand)
    expect(Cask::Utils).to receive(:gain_permissions_remove).with(root/"var/protected", command:)

    Homebrew::InstallSteps::Runner.new(context:, command:).run(steps)
  end

  specify "replaces literal and regular expression matches", :aggregate_failures do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      inreplace "literal.txt", "before", "after"
      inreplace "pattern.txt", /before.+after/i, "replaced"
    end

    (root/"var").mkpath
    (root/"var/literal.txt").write "before"
    (root/"var/pattern.txt").write "BEFORE and AFTER"

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect((root/"var/literal.txt").read).to eq("after")
    expect((root/"var/pattern.txt").read).to eq("replaced")
  end

  specify "warns inside a matching path scope" do
    steps = Homebrew::InstallSteps::DSL.build do
      if_path_exists "{{var}}/{missing,conflict}" do
        warn "{{token}} conflict"
      end
    end
    named_context = context
    named_context.define_singleton_method(:name) { ["Example"] }
    named_context.define_singleton_method(:token) { "example" }
    (root/"var/conflict").mkpath
    runner = Homebrew::InstallSteps::Runner.new(context: named_context)
    expect(runner).to receive(:opoo).with("example conflict")

    runner.run(steps)
  end

  specify "runs serialised commands" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      run "helper", args: ["--path={{var}}"], base: :libexec, env: { "EXAMPLE" => "{{var}}/value" }
    end

    command = class_double(SystemCommand)
    expect(command).to receive(:run!)
      .with(root/"prefix/libexec/helper", args: ["--path=#{root}/var"], sudo: false,
                                           env: { "EXAMPLE" => "#{root}/var/value" }, input: [], print_stdout: false,
                                           print_stderr: true, reset_uid: true, chdir: nil)

    Homebrew::InstallSteps::Runner.new(context:, command:).run(steps)
  end

  specify "serialises command environments as JSON objects" do
    steps = Homebrew::InstallSteps::DSL.build do
      run "helper", env: { "EXAMPLE" => "{{formula_name}}" },
                    writable_paths: ["Library/Application Support/Example"], writable_base: :home
    end

    expect(steps).to include(a_hash_including(
                               "type"           => "run",
                               "env"            => { "EXAMPLE" => "{{formula_name}}" },
                               "writable_paths" => [
                                 { "base" => "home", "path" => "Library/Application Support/Example" },
                               ],
                             ))
  end

  specify "runs commands with serialised input and output paths" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      run "filter", base: :bin, stdin_path: "input.txt", stdout_path: "output.txt", chdir: "work"
    end

    (root/"var/work").mkpath
    (root/"var/input.txt").write "input"
    result = instance_double(SystemCommand::Result, stdout: "output")
    command = class_double(SystemCommand)
    expect(command).to receive(:run!)
      .with(root/"prefix/bin/filter", args: [], sudo: false, env: {}, input: "input", print_stdout: false,
                                      print_stderr: true, reset_uid: true, chdir: root/"var/work")
      .and_return(result)

    Homebrew::InstallSteps::Runner.new(context:, command:).run(steps)

    expect((root/"var/output.txt").read).to eq("output")
  end

  specify "can ignore process termination failure after retries" do
    steps = Homebrew::InstallSteps::DSL.build do
      terminate_process "/Applications/Example.app", match: :full, attempts: 3,
                                                       notices: ["Closing {{name}}"],
                                                       failure_message: "Unable to close {{name}}"
    end

    named_context = context
    named_context.define_singleton_method(:name) { "Example" }
    command = class_double(SystemCommand)
    runner = Homebrew::InstallSteps::Runner.new(context: named_context, command:)
    allow(runner).to receive(:sleep)
    expect(runner).to receive(:ohai).with("Closing Example")
    expect(runner).to receive(:opoo).with("Unable to close Example")
    expect(command).to receive(:run!)
      .with("/usr/bin/pkill", args: ["-f", "/Applications/Example.app"], sudo: false,
                              print_stdout: true, print_stderr: true, reset_uid: true)
      .exactly(3).times
      .and_raise(ErrorDuringExecution.new([], status: 1))

    expect { runner.run(steps) }.not_to raise_error
  end

  specify "rejects unknown process match modes" do
    expect do
      Homebrew::InstallSteps::DSL.build do
        terminate_process "Example", match: :prefix
      end
    end.to raise_error(ArgumentError, "terminate_process match must be :name or :full")
  end

  specify "rejects non-positive process termination attempts" do
    expect do
      Homebrew::InstallSteps::DSL.build do
        terminate_process "Example", attempts: 0
      end
    end.to raise_error(ArgumentError, "terminate_process attempts must be positive")
  end

  specify "uses killall for exact process names" do
    steps = Homebrew::InstallSteps::DSL.build do
      terminate_process "Example", must_succeed: true
    end

    command = class_double(SystemCommand)
    expect(command).to receive(:run!)
      .with("/usr/bin/killall", args: ["Example"], sudo: false,
                                print_stdout: true, print_stderr: true, reset_uid: true)

    Homebrew::InstallSteps::Runner.new(context:, command:).run(steps)
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

  specify "raises when a write step has missing content" do
    expect do
      Homebrew::InstallSteps::Runner.new(context:).run([{ "type" => "write", "path" => "config/new.conf" }])
    end.to raise_error(ArgumentError, /requires content/)
  end

  specify "runs service data directory initialisers", :aggregate_failures do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      init_data_dir "postgresql@16", using: :postgresql
      init_data_dir "postgresql@12", using: :postgresql, locale: "C"
      init_data_dir "mysql", using: :mysql
      init_data_dir "mysql", using: :mariadb
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
      symlink_tree "include/postgresql", "include/#{formula_name}"
      symlink_tree "lib/postgresql", "lib/#{formula_name}"
      symlink_tree "share/postgresql", "share/#{formula_name}"
      symlink_children "bin", suffix: "-#{version.major}"
      init_data_dir formula_name, using: :postgresql
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
      init_data_dir "postgresql@16", using: :postgresql
    end

    ENV["HOMEBREW_GITHUB_ACTIONS"] = "1"

    runner = Homebrew::InstallSteps::Runner.new(context:)
    expect(runner).not_to receive(:run_command)

    runner.run(steps)

    expect(root/"var/postgresql@16").to be_a_directory
  end

  specify "skips data directory initialisers when their marker exists", :aggregate_failures do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :var) do
      init_data_dir "mysql", using: :mysql
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
    stub_const("HOMEBREW_PREFIX", root/"homebrew")
    %w[
      opt/glib/bin/glib-compile-schemas
      opt/glib/bin/gio-querymodules
      opt/gdk-pixbuf/bin/gdk-pixbuf-query-loaders
      opt/shared-mime-info/bin/update-mime-database
      opt/desktop-file-utils/bin/update-desktop-database
    ].each do |path|
      create_executable HOMEBREW_PREFIX/path
    end
    steps = Homebrew::InstallSteps::DSL.build do
      compile_gsettings_schemas
      update_gio_modules_cache
      update_gdk_pixbuf_loaders_cache
      update_mime_database
      update_desktop_database
    end

    runner = Homebrew::InstallSteps::Runner.new(context:)
    expect(runner).to receive(:run_command).with(root/"homebrew/opt/glib/bin/glib-compile-schemas",
                                                 HOMEBREW_PREFIX/"share/glib-2.0/schemas").ordered
    expect(runner).to receive(:run_command).with(root/"homebrew/opt/glib/bin/gio-querymodules",
                                                 HOMEBREW_PREFIX/"lib/gio/modules").ordered
    expect(runner).to receive(:run_command)
      .with(root/"homebrew/opt/gdk-pixbuf/bin/gdk-pixbuf-query-loaders", "--update-cache").ordered
    expect(runner).to receive(:run_command).with(root/"homebrew/opt/shared-mime-info/bin/update-mime-database",
                                                 HOMEBREW_PREFIX/"share/mime").ordered
    expect(runner).to receive(:run_command)
      .with(root/"homebrew/opt/desktop-file-utils/bin/update-desktop-database",
            HOMEBREW_PREFIX/"share/applications").ordered

    runner.run(steps)
  end

  specify "reports missing formula helper executables" do
    stub_const("HOMEBREW_PREFIX", root/"homebrew")
    steps = Homebrew::InstallSteps::DSL.build do
      compile_gsettings_schemas
    end

    expect { Homebrew::InstallSteps::Runner.new(context:).run(steps) }
      .to raise_error(ArgumentError, %r{glib is missing required executable: .*/opt/glib/bin/glib-compile-schemas})
  end

  specify "dispatches GCC runtime configuration" do
    steps = Homebrew::InstallSteps::DSL.build do
      configure_gcc_runtime
    end

    runner = Homebrew::InstallSteps::Runner.new(context:)
    expect(runner).to receive(:run_configure_gcc_runtime)

    runner.run(steps)
  end

  specify "configures GCC runtime files on Linux", :aggregate_failures do
    steps = Homebrew::InstallSteps::DSL.build do
      configure_gcc_runtime
    end
    gcc_context = context
    gcc_context.define_singleton_method(:name) { "gcc" }
    libgcc = root/"gcc/lib/gcc/15"
    crtdir = root/"system/lib"
    libgcc.mkpath
    crtdir.mkpath
    crti = crtdir/"crti.o"
    crti.write "crt"
    specs = libgcc/"specs"
    specs.write "old specs"
    Pathname("#{specs}.orig").write "old original specs"
    gcc = root/"prefix/bin/gcc-15"
    original_specs = "*link:\n+ %o \n"

    allow(Homebrew::SimulateSystem).to receive(:simulating_or_running_on_linux?).and_return(true)
    allow(Utils::Path).to receive(:formula_any_version_installed?).with("glibc").and_return(false)
    allow(Utils::Path).to receive(:formula_opt_lib).with("glibc").and_return(root/"glibc/lib")
    runner = Homebrew::InstallSteps::Runner.new(context: gcc_context)
    expect(runner).to receive(:context_version_major).and_return("15")
    expect(runner).to receive(:run_command_output)
      .with(gcc, "-print-libgcc-file-name").ordered
      .and_return("#{libgcc}/libgcc_s.so\n")
    expect(runner).to receive(:run_command_output)
      .with("/usr/bin/cc", "-print-file-name=crti.o").ordered
      .and_return("#{crti}\n")
    expect(runner).to receive(:run_command_output)
      .with(gcc, "-print-multiarch").ordered
      .and_return("x86_64-linux-gnu\n")
    expect(runner).to receive(:run_command_output).with(gcc, "-dumpspecs").ordered.and_return(original_specs)
    expect(FileUtils).to receive(:ln_sf).with([crti.to_s], libgcc).and_call_original
    expect(FileUtils).to receive(:rm_f).with(["#{specs}.orig", specs]).and_call_original

    runner.run(steps)

    expect(libgcc/"crti.o").to be_a_symlink
    expect((libgcc/"crti.o").readlink).to eq(crti)
    expect(Pathname("#{specs}.orig").read).to eq(original_specs)
    expect(specs.read).to include("%(homebrew_rpath)", "-idirafter /usr/include/x86_64-linux-gnu")
  end

  specify "dispatches gzipped executable installation" do
    steps = Homebrew::InstallSteps::DSL.build do
      install_gzipped_executable "compressed.gz", "bin/executable"
    end

    runner = Homebrew::InstallSteps::Runner.new(context:)
    expect(runner).to receive(:run_install_gzipped_executable)

    runner.run(steps)
  end

  specify "installs a gzipped executable with a fixed mode", :aggregate_failures do
    require "zlib"

    source = root/"prefix/bin/executable.gz"
    source.dirname.mkpath
    Zlib::GzipWriter.open(source.to_s) do |gzip|
      gzip.orig_name = "stored-name"
      gzip.write "executable"
    end
    stored_name = source.dirname/"stored-name"
    stored_name.write "preserve"
    steps = Homebrew::InstallSteps::DSL.build(default_source_base: :prefix, default_target_base: :prefix) do
      install_gzipped_executable "bin/executable.gz", "bin/executable"
    end

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    target = root/"prefix/bin/executable"
    expect(target.read).to eq("executable")
    expect(target.stat.mode & 0777).to eq(0755)
    expect(source).not_to exist
    expect(stored_name.read).to eq("preserve")
  end

  specify "dispatches glibc runtime configuration" do
    steps = Homebrew::InstallSteps::DSL.build do
      configure_glibc_runtime
    end

    runner = Homebrew::InstallSteps::Runner.new(context:)
    expect(runner).to receive(:run_configure_glibc_runtime)

    runner.run(steps)
  end

  specify "configures glibc locales and timezone links", :aggregate_failures do
    steps = Homebrew::InstallSteps::DSL.build do
      configure_glibc_runtime
    end
    glibc_context = context
    root_path = root
    glibc_context.define_singleton_method(:name) { "glibc" }
    glibc_context.define_singleton_method(:lib) { root_path/"prefix/lib" }
    glibc_context.define_singleton_method(:etc) { root_path/"prefix/etc" }
    glibc_context.define_singleton_method(:share) { root_path/"prefix/share" }
    (root/"prefix/etc").mkpath
    (root/"prefix/share").mkpath
    ENV.delete_if { |key,| key == "HOMEBREW_LANG" || key == "LANG" || key.start_with?("LC_") }
    ENV["HOMEBREW_LANG"] = "de_DE.utf8"
    ENV["LANG"] = "C"
    ENV["LC_TIME"] = "en_GB"
    timezone_sources = [Pathname("/etc/localtime"), Pathname("/usr/share/zoneinfo")]
    allow_any_instance_of(Pathname).to receive(:exist?).and_wrap_original do |method, *args|
      timezone_sources.include?(method.receiver) || method.call(*args)
    end

    runner = Homebrew::InstallSteps::Runner.new(context: glibc_context)
    localedef = root/"prefix/bin/localedef"
    expect(runner).to receive(:ohai).with("Installing locale data for de_DE.utf8 en_GB en_US.UTF-8")
    expect(runner).to receive(:run_command)
      .with(localedef, "-i", "de_DE", "-f", "UTF-8", "de_DE.utf8").ordered
    expect(runner).to receive(:run_command).with(localedef, "-i", "en_GB", "en_GB").ordered
    expect(runner).to receive(:run_command)
      .with(localedef, "-i", "en_US", "-f", "UTF-8", "en_US.UTF-8").ordered

    runner.run(steps)

    expect(root/"prefix/lib/locale").to be_a_directory
    expect(root/"prefix/etc/localtime").to be_a_symlink
    expect((root/"prefix/etc/localtime").readlink).to eq(Pathname("/etc/localtime"))
    expect(root/"prefix/share/zoneinfo").to be_a_symlink
    expect((root/"prefix/share/zoneinfo").readlink).to eq(Pathname("/usr/share/zoneinfo"))
  end

  specify "dispatches Clang system configuration" do
    steps = Homebrew::InstallSteps::DSL.build do
      configure_clang_system
    end

    runner = Homebrew::InstallSteps::Runner.new(context:)
    expect(runner).to receive(:run_configure_clang_system)

    runner.run(steps)
  end

  specify "repairs incomplete Clang system configuration" do
    require "utils/clang"

    steps = Homebrew::InstallSteps::DSL.build do
      configure_clang_system
    end
    clang_context = context
    root_path = root
    clang_context.define_singleton_method(:etc) { root_path/"prefix/etc" }
    config_dir = root/"prefix/etc/clang"
    config_dir.mkpath
    (config_dir/"arm64-apple-darwin23.cfg").write ""
    (config_dir/"arm64-apple-macosx14.cfg").write ""
    macos_version = MacOSVersion.new("14")
    stub_const("MacOS", Module.new do
      define_singleton_method(:version) { macos_version }
    end)
    allow(Homebrew::SimulateSystem).to receive(:simulating_or_running_on_macos?).and_return(true)
    allow(OS).to receive(:kernel_version).and_return(Version.new("23"))
    allow(Hardware::CPU).to receive(:arch).and_return(:arm64)
    expect(Utils::Clang).to receive(:write_system_config_files).with(
      config_dir:,
      macos_version:,
      kernel_version: "23",
      arch:           :arm64,
    )

    Homebrew::InstallSteps::Runner.new(context: clang_context).run(steps)
  end

  describe "configures PHP" do
    let(:steps) do
      Homebrew::InstallSteps::DSL.build do
        configure_php
      end
    end
    let(:homebrew_prefix) { root/"homebrew" }
    let(:pear_prefix) { root/"prefix/share/php@8.4/pear" }
    let(:pecl_path) { homebrew_prefix/"lib/php/pecl" }
    let(:ext_config_path) { homebrew_prefix/"etc/php/8.4/conf.d/ext-opcache.ini" }
    let(:php_context) do
      root_path = root
      context.tap do |value|
        value.define_singleton_method(:name) { "php@8.4" }
        value.define_singleton_method(:version) { Version.new("8.4.1") }
        value.define_singleton_method(:pkgshare) { root_path/"prefix/share/php@8.4" }
        value.define_singleton_method(:opt_prefix) { root_path/"opt/php@8.4" }
        value.define_singleton_method(:etc) { root_path/"homebrew/etc" }
      end
    end
    let(:runner) { Homebrew::InstallSteps::Runner.new(context: php_context) }

    before do
      stub_const("HOMEBREW_PREFIX", homebrew_prefix)
      (pear_prefix/".channels/.alias").mkpath
      (pear_prefix/".channels/pear.php.net.reg").write "channel"
      (pear_prefix/".channels/.alias/pear.txt").write "alias"
      (pear_prefix/".depdblock").write "lock"
      FileUtils.chmod 0700, [pear_prefix/".channels", pear_prefix/".channels/.alias"]
      FileUtils.chmod 0600, [pear_prefix/".channels/pear.php.net.reg", pear_prefix/".channels/.alias/pear.txt",
                             pear_prefix/".depdblock"]
      (homebrew_prefix/"share").mkpath
      File.symlink root/"missing-pecl", root/"prefix/pecl"
      allow(runner).to receive(:run_command_output)
        .with(root/"prefix/bin/php-config", "--extension-dir")
        .and_return("/usr/local/lib/php/20240924\n")
      allow(runner).to receive(:run_command)
    end

    specify "updates PEAR, PECL and opcache configuration", :aggregate_failures do
      expect(runner).to receive(:run_command).with(
        root/"prefix/bin/pear", "config-set", "ext_dir", pecl_path/"20240924", "system"
      ).ordered
      expect(runner).to receive(:run_command).with(root/"prefix/bin/pear", "update-channels").ordered

      runner.run(steps)

      expect((pear_prefix/".channels").stat.mode & 0777).to eq(0755)
      expect((pear_prefix/".channels/.alias").stat.mode & 0777).to eq(0755)
      expect((pear_prefix/".channels/pear.php.net.reg").stat.mode & 0777).to eq(0644)
      expect((pear_prefix/".channels/.alias/pear.txt").stat.mode & 0777).to eq(0644)
      expect((pear_prefix/".depdblock").stat.mode & 0777).to eq(0644)
      expect(root/"prefix/pecl").to be_a_symlink
      expect((root/"prefix/pecl").readlink).to eq(pecl_path)
      expect(pecl_path/"20240924").to be_a_directory
      expect(homebrew_prefix/"share/pear@8.4/.depdblock").to exist
      expect(ext_config_path.read).to eq <<~INI
        [opcache]
        zend_extension="#{root}/opt/php@8.4/lib/php/20240924/opcache.so"
      INI
    end

    specify "only replaces the active opcache extension setting" do
      ext_config_path.dirname.mkpath
      ext_config_path.write <<~INI
        ; zend_extension=keep.so
          zend_extension = old.so
        description=zend_extension=also-keep
      INI

      runner.run(steps)

      expect(ext_config_path.read).to eq <<~INI
        ; zend_extension=keep.so
        zend_extension="#{root}/opt/php@8.4/lib/php/20240924/opcache.so"
        description=zend_extension=also-keep
      INI
    end

    specify "audits existing opcache extension settings" do
      ext_config_path.dirname.mkpath
      ext_config_path.write "[opcache]\n"

      expect { runner.run(steps) }.to raise_error(Utils::Inreplace::Error)
    end
  end

  specify "dispatches CPython and PyPy bootstrap" do
    steps = Homebrew::InstallSteps::DSL.build do
      bootstrap_cpython
      bootstrap_pypy abi_version: "3.10"
    end

    runner = Homebrew::InstallSteps::Runner.new(context:)
    expect(runner).to receive(:run_bootstrap_cpython).ordered
    expect(runner).to receive(:run_bootstrap_pypy).with("3.10").ordered

    runner.run(steps)
  end

  specify "bootstraps CPython 3.9 configuration", :aggregate_failures do
    python = api_formula("python@3.9", "3.9.1")
    allow(python).to receive(:prefix).and_return(root/"prefix")
    stub_const("HOMEBREW_PREFIX", root/"homebrew")
    allow(Homebrew::SimulateSystem).to receive(:simulating_or_running_on_macos?).and_return(false)
    site_packages = root/"homebrew/lib/python3.9/site-packages"
    site_packages_cellar = root/"prefix/lib/python3.9/site-packages"
    bundled = root/"prefix/lib/python3.9/ensurepip/_bundled"
    bundled.mkpath
    setuptools_wheel = bundled/"setuptools-1.0-py3-none-any.whl"
    pip_wheel = bundled/"pip-1.0-py3-none-any.whl"
    wheel = root/"prefix/libexec/wheel-1.0-py3-none-any.whl"
    [setuptools_wheel, pip_wheel, wheel].each do |path|
      path.dirname.mkpath
      path.write "wheel"
    end
    (site_packages_cellar/"old.pth").tap do |path|
      path.dirname.mkpath
      path.write "old"
    end
    (site_packages/"bin").mkpath
    (site_packages/"bin/pip3.9").write "pip"
    (site_packages/"bin/wheel").write "wheel"
    (root/"prefix/bin").mkpath
    (root/"prefix/lib/python3.9/distutils").mkpath
    (root/"homebrew/bin").mkpath
    runner = Homebrew::InstallSteps::Runner.new(context: python)
    pip_install_args = []
    allow(runner).to receive(:run_command) do |*args|
      next unless args.include?("--target=#{site_packages}")

      pip_install_args.concat(args)
      framework_compat = site_packages/"setuptools/_distutils/command/_framework_compat.py"
      framework_compat.dirname.mkpath
      framework_compat.write "    homebrew_prefix = None\n"
    end
    steps = Homebrew::InstallSteps::DSL.build do
      bootstrap_cpython
    end

    runner.run(steps)

    expect(site_packages_cellar).to be_a_symlink
    expect(site_packages_cellar.realpath).to eq(site_packages.realpath)
    expect(site_packages_cellar/"old.pth").not_to exist
    expect((root/"prefix/lib/python3.9/distutils/distutils.cfg").read).to eq <<~INI
      [install]
      prefix=#{root}/homebrew
      [build_ext]
      include_dirs=#{root}/homebrew/include:#{root}/homebrew/opt/openssl@3/include:#{root}/homebrew/opt/sqlite/include
      library_dirs=#{root}/homebrew/lib:#{root}/homebrew/opt/openssl@3/lib:#{root}/homebrew/opt/sqlite/lib
    INI
    expect((site_packages/"setuptools/_distutils/command/_framework_compat.py").read)
      .to eq("    homebrew_prefix = '#{root}/homebrew'\n")
    expect(pip_install_args).to include(setuptools_wheel, pip_wheel, wheel)
    expect(python).to be_loaded_from_api
  end

  specify "bootstraps PyPy 3.10 configuration", :aggregate_failures do
    require "rubygems/package"
    require "zlib"

    pypy = api_formula("pypy3.10", "7.3.20")
    allow(pypy).to receive_messages(
      prefix:   root/"prefix",
      libexec:  root/"prefix/libexec",
      pkgshare: root/"prefix/share/pypy3",
    )
    stub_const("HOMEBREW_PREFIX", root/"homebrew")
    post_install_resources = root/"prefix/libexec/post-install-resources"
    %w[setuptools pip].each do |package|
      archive = post_install_resources/"#{package}.tar.gz"
      archive.dirname.mkpath
      Zlib::GzipWriter.open(archive.to_s) do |gzip|
        Gem::Package::TarWriter.new(gzip) do |tar|
          contents = package
          tar.mkdir "#{package}-1.0", 0755
          tar.add_file_simple "#{package}-1.0/setup.py", 0644, contents.bytesize do |file|
            file.write contents
          end
        end
      end
    end
    scripts_folder = root/"homebrew/share/pypy3.10"
    scripts_folder.mkpath
    (scripts_folder/"pip3.10").write "pip"
    (root/"prefix/libexec/lib/pypy3.10/distutils").mkpath
    command = class_double(SystemCommand, run: nil)
    runner = Homebrew::InstallSteps::Runner.new(context: pypy, command:)
    installed_packages = []
    allow(runner).to receive(:run_command) do |_, *args|
      installed_packages << (Pathname.pwd/"setup.py").read if args.include?("setup.py")
    end
    steps = Homebrew::InstallSteps::DSL.build do
      bootstrap_pypy abi_version: "3.10"
    end

    runner.run(steps)

    site_packages = root/"homebrew/lib/pypy3.10/site-packages"
    libexec_site_packages = root/"prefix/libexec/lib/pypy3.10/site-packages"
    expect(site_packages/".keepme").to exist
    expect(libexec_site_packages).to be_a_symlink
    expect(libexec_site_packages.realpath).to eq(site_packages.realpath)
    expect((root/"prefix/libexec/lib/pypy3.10/distutils/distutils.cfg").read).to eq <<~INI
      [install]
      install-scripts=#{scripts_folder}
    INI
    expect(root/"prefix/bin/pip_pypy3.10").to be_a_symlink
    expect(root/"homebrew/bin/pip_pypy3.10").to be_a_symlink
    expect(installed_packages).to contain_exactly("setuptools", "pip")
    expect(pypy).to be_loaded_from_api
  end

  specify "makes CPython venv activation script templates writable", :aggregate_failures do
    script = root/"lib/venv/scripts/common/activate"
    directory = root/"lib/venv/scripts/directory"
    script.dirname.mkpath
    directory.mkpath
    script.write "activate"
    FileUtils.chmod 0444, script
    FileUtils.chmod 0555, directory

    Homebrew::InstallSteps::Runner.new(context:).make_cpython_venv_activation_scripts_writable(root/"lib")

    expect(script.stat.mode & 0200).to eq(0200)
    expect(directory.stat.mode & 0200).to be_zero
  end

  describe "runs update_gtk_icon_cache rebuild action" do
    let(:steps) do
      Homebrew::InstallSteps::DSL.build do
        update_gtk_icon_cache
      end
    end

    it "with gtk4" do
      stub_const("HOMEBREW_PREFIX", root/"homebrew")
      create_executable HOMEBREW_PREFIX/"opt/gtk4/bin/gtk4-update-icon-cache"
      allow(Utils::Path).to receive(:formula_any_version_installed?).with("gtk4").and_return(true)
      runner = Homebrew::InstallSteps::Runner.new(context:)
      expect(runner).to receive(:run_command)
        .with(root/"homebrew/opt/gtk4/bin/gtk4-update-icon-cache", "-q", "-t", "-f",
              HOMEBREW_PREFIX/"share/icons/hicolor").ordered
      runner.run(steps)
    end

    it "with gtk+3" do
      stub_const("HOMEBREW_PREFIX", root/"homebrew")
      create_executable HOMEBREW_PREFIX/"opt/gtk+3/bin/gtk3-update-icon-cache"
      allow(Utils::Path).to receive(:formula_any_version_installed?).with("gtk4").and_return(false)
      runner = Homebrew::InstallSteps::Runner.new(context:)
      expect(runner).to receive(:run_command)
        .with(root/"homebrew/opt/gtk+3/bin/gtk3-update-icon-cache", "-q", "-t", "-f",
              HOMEBREW_PREFIX/"share/icons/hicolor").ordered
      runner.run(steps)
    end
  end

  specify "deletes matching keychain certificates by SHA-256 hash" do
    steps = Homebrew::InstallSteps::DSL.build do
      delete_keychain_certificates "Charles"
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
      delete_keychain_certificates "NodeMITMProxyCA", fingerprint_of: certificate
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
      delete_keychain_certificates "NodeMITMProxyCA", fingerprint_of: certificate
    end

    runner = Homebrew::InstallSteps::Runner.new(context:)
    expect(runner).not_to receive(:run_command_output)
    expect(runner).not_to receive(:run_command)

    runner.run(steps)
  end

  specify "sets permissions and ownership for existing cask step paths" do
    steps = Homebrew::InstallSteps::DSL.build(default_base: :staged_path) do
      set_permissions ["Prepared.app", "Missing.app"], "0755"
      set_permissions "Prepared.file", "0644", recursive: false
      set_ownership "Owned.app", user: "root", group: "wheel"
      set_ownership "Owned.file", user: "root", group: "wheel", recursive: false
    end

    command = class_double(SystemCommand)
    (root/"stage/Prepared.app").mkpath
    (root/"stage/Prepared.file").write ""
    (root/"stage/Owned.app").mkpath
    (root/"stage/Owned.file").write ""

    allow(Cask::Quarantine).to receive(:app_management_permissions_granted?)
      .with(app: root/"stage/Owned.app", command:)
      .and_return(true)
    allow(Cask::Quarantine).to receive(:app_management_permissions_granted?)
      .with(app: root/"stage/Owned.file", command:)
      .and_return(true)
    expect(command).to receive(:run!)
      .with("chmod", args: ["-R", "--", "0755", root/"stage/Prepared.app"], sudo: false).ordered
    expect(command).to receive(:run!)
      .with("chmod", args: ["--", "0644", root/"stage/Prepared.file"], sudo: false).ordered
    expect(command).to receive(:run!)
      .with("chown", args: ["-R", "--", "root:wheel", root/"stage/Owned.app"], sudo: true).ordered
    expect(command).to receive(:run!)
      .with("chown", args: ["--", "root:wheel", root/"stage/Owned.file"], sudo: true).ordered

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

  specify "moves a directory's contents" do
    steps = Homebrew::InstallSteps::DSL.build(default_source_base: :staged_path, default_target_base: :staged_path) do
      move_contents ".", "Nested"
    end
    (root/"stage").mkpath
    (root/"stage/source-file").write "source"

    Homebrew::InstallSteps::Runner.new(context:).run(steps)

    expect(root/"stage/Nested/source-file").to exist
  end

  specify "uses sudo only when an if-needed symlink target is not writable" do
    steps = Homebrew::InstallSteps::DSL.build(default_target_base: :staged_path) do
      symlink "target", "writable/linked-target", source_base: :relative, sudo: :if_needed
      symlink "target", "protected/linked-target", source_base: :relative, sudo: :if_needed
    end
    protected_dir = root/"stage/protected"
    (root/"stage/writable").mkpath
    protected_dir.mkpath
    FileUtils.chmod "-w", protected_dir
    command = class_double(SystemCommand)
    expect(command).to receive(:run!)
      .with("/bin/ln", args: ["-s", "target", protected_dir/"linked-target"], sudo: true)

    begin
      Homebrew::InstallSteps::Runner.new(context:, command:).run(steps)
    ensure
      FileUtils.chmod "+w", protected_dir
    end

    expect(root/"stage/writable/linked-target").to be_a_symlink
  end

  specify "removes symlinks marked for uninstall" do
    steps = Homebrew::InstallSteps::DSL.build(default_target_base: :staged_path) do
      symlink "target", "linked-target", source_base: :relative, overwrite: true, remove_on_uninstall: true
    end

    (root/"stage").mkpath
    File.symlink "target", root/"stage/linked-target"

    Homebrew::InstallSteps::Runner.new(context:).run(steps, phase: :uninstall)

    expect(root/"stage/linked-target").not_to be_a_symlink
  end

  specify "preserves symlinks with unexpected targets on uninstall" do
    steps = Homebrew::InstallSteps::DSL.build(default_target_base: :staged_path) do
      symlink "target", "linked-target", source_base: :relative, uninstall: true
    end
    (root/"stage").mkpath
    File.symlink "different-target", root/"stage/linked-target"

    Homebrew::InstallSteps::Runner.new(context:).run(steps, phase: :uninstall)

    expect(root/"stage/linked-target").to be_a_symlink
  end

  specify "uses elevated removal for matching symlinks when needed" do
    steps = Homebrew::InstallSteps::DSL.build(default_target_base: :staged_path) do
      symlink "target", "protected/linked-target", source_base: :relative, uninstall: true, sudo: :if_needed
    end
    protected_dir = root/"stage/protected"
    protected_dir.mkpath
    target = protected_dir/"linked-target"
    File.symlink "target", target
    FileUtils.chmod "-w", protected_dir
    command = class_double(SystemCommand)
    expect(Cask::Utils).to receive(:gain_permissions_remove).with(target, command:)

    begin
      Homebrew::InstallSteps::Runner.new(context:, command:).run(steps, phase: :uninstall)
    ensure
      FileUtils.chmod "+w", protected_dir
    end
  end

  specify "does not expose the surrounding formula or cask DSL" do
    expect do
      Homebrew::InstallSteps::DSL.build(default_base: :var) do
        system "true"
      end
    end.to raise_error(NameError)
  end
end
