# typed: false
# frozen_string_literal: true

require "formula"

RSpec.describe "patching", type: :system do
  let(:formula_subclass) do
    Class.new(Formula) do
      extend Test::Helper::Fixtures

      def self.resource(*, **, &block)
        super do
          extend Test::Helper::Fixtures

          define_singleton_method :patch do |*patch_args, **patch_kwargs, &patch_block|
            super(*patch_args, **patch_kwargs) do
              extend Test::Helper::Fixtures

              instance_eval(&patch_block)
            end
          end

          instance_eval(&block) if block
        end
      end

      def self.patch(*, **, &block)
        super do
          extend Test::Helper::Fixtures

          instance_eval(&block) if block
        end
      end

      url "file://#{tarball_fixture("testball-0.1.tbz")}"
      sha256 tarball_fixture_sha256("testball-0.1.tbz")
    end
  end

  def formula(name = "formula_name", path: Formulary.core_path(name), spec: :stable, alias_path: nil, tap: nil,
              &block)
    formula_subclass.class_eval(&block)
    formula_subclass.new(name, path, spec, alias_path:, tap:)
  end

  matcher :be_patched do
    match do |formula|
      formula.brew do
        formula.patch
        s = File.read("libexec/NOOP")
        expect(s).not_to include("NOOP"), "libexec/NOOP was not patched as expected"
        expect(s).to include("ABCD"), "libexec/NOOP was not patched as expected"
      end
    end
  end

  matcher :be_patched_with_homebrew_prefix do
    match do |formula|
      formula.brew do
        formula.patch
        s = File.read("libexec/NOOP")
        expect(s).not_to include("NOOP"), "libexec/NOOP was not patched as expected"
        expect(s).not_to include("@@HOMEBREW_PREFIX@@"), "libexec/NOOP was not patched as expected"
        expect(s).to include(HOMEBREW_PREFIX.to_s), "libexec/NOOP was not patched as expected"
      end
    end
  end

  matcher :have_its_resource_patched do
    match do |formula|
      formula.brew do
        formula.resources.first.stage Pathname.pwd/"resource_dir"
        s = File.read("resource_dir/libexec/NOOP")
        expect(s).not_to include("NOOP"), "libexec/NOOP was not patched as expected"
        expect(s).to include("ABCD"), "libexec/NOOP was not patched as expected"
      end
    end
  end

  matcher :be_sequentially_patched do
    match do |formula|
      formula.brew do
        formula.patch
        s = File.read("libexec/NOOP")
        expect(s).not_to include("NOOP"), "libexec/NOOP was not patched as expected"
        expect(s).not_to include("ABCD"), "libexec/NOOP was not patched as expected"
        expect(s).to include("1234"), "libexec/NOOP was not patched as expected"
      end
    end
  end

  matcher :miss_apply do
    match do |formula|
      expect do
        formula.brew do
          formula.patch
        end
      end.to raise_error(MissingApplyError)
    end
  end

  specify "single_patch_dsl" do
    expect(
      formula do
        T.bind(self, T.class_of(Formula))
        patch do
          url "file://#{patch_fixture("noop-a")}"
          sha256 patch_fixture_sha256("noop-a")
        end
      end,
    ).to be_patched
  end

  specify "local_patch_dsl_resolves_path_loaded_formulae_from_formula_directory" do
    expect(
      formula(path: fixture("testball.rb")) do
        T.bind(self, T.class_of(Formula))
        patch do
          file "patches/noop-a.diff"
        end
      end,
    ).to be_patched
  end

  specify "local_patch_dsl_with_directory" do
    expect(
      formula(path: fixture("testball.rb")) do
        T.bind(self, T.class_of(Formula))
        patch do
          file "patches/noop-b.diff"
          directory "libexec"
        end
      end,
    ).to be_patched
  end

  specify "local_patch_dsl_with_strip" do
    expect(
      formula(path: fixture("testball.rb")) do
        T.bind(self, T.class_of(Formula))
        patch :p0 do
          file "patches/noop-b.diff"
        end
      end,
    ).to be_patched
  end

  specify "local_patch_dsl_with_homebrew_prefix" do
    expect(
      formula(path: fixture("testball.rb")) do
        T.bind(self, T.class_of(Formula))
        patch do
          file "patches/noop-d.diff"
        end
      end,
    ).to be_patched_with_homebrew_prefix
  end

  specify "local_patch_dsl_resolves_tapped_formulae_from_tap_root" do
    tap = Tap.fetch("homebrew", "local-patch-test")
    (tap.path/"Formula").mkpath
    (tap.path/"patches").mkpath
    FileUtils.cp patch_fixture("noop-a"), tap.path/"patches/noop-a.diff"

    expect(
      formula(path: tap.path/"Formula/testball.rb", tap:) do
        T.bind(self, T.class_of(Formula))
        patch do
          file "patches/noop-a.diff"
        end
      end,
    ).to be_patched
  ensure
    FileUtils.rm_rf tap.path if tap
  end

  specify "local_patch_dsl_missing_file_fail" do
    f = formula(path: fixture("testball.rb")) do
      T.bind(self, T.class_of(Formula))
      patch do
        file "patches/missing.diff"
      end
    end

    expect { f.stable.patches.last.contents }
      .to raise_error(ArgumentError, "Patch file does not exist: patches/missing.diff")
  end

  specify "local_patch_dsl_directory_fail" do
    f = formula(path: fixture("testball.rb")) do
      T.bind(self, T.class_of(Formula))
      patch do
        file "patches"
      end
    end

    expect { f.stable.patches.last.contents }
      .to raise_error(ArgumentError, "Patch file must be a file: patches")
  end

  specify "local_patch_dsl_rejects_symlink_escape" do
    mktmpdir do |tmpdir|
      repository = tmpdir/"repository"
      repository.mkpath
      FileUtils.cp patch_fixture("noop-a"), tmpdir/"outside.diff"
      FileUtils.ln_s tmpdir/"outside.diff", repository/"escape.diff"

      f = formula(path: repository/"testball.rb") do
        T.bind(self, T.class_of(Formula))
        patch do
          file "escape.diff"
        end
      end

      expect { f.stable.patches.last.contents }
        .to raise_error(ArgumentError, "Patch file must be within the formula repository.")
    end
  end

  specify "single_patch_dsl_for_resource" do
    expect(
      formula do
        T.bind(self, T.class_of(Formula))
        resource "some_resource" do
          url "file://#{tarball_fixture("testball-0.1.tbz")}"
          sha256 tarball_fixture_sha256("testball-0.1.tbz")

          patch do
            url "file://#{patch_fixture("noop-a")}"
            sha256 patch_fixture_sha256("noop-a")
          end
        end
      end,
    ).to have_its_resource_patched
  end

  specify "single_patch_dsl_with_apply" do
    expect(
      formula do
        T.bind(self, T.class_of(Formula))
        patch do
          url "file://#{tarball_fixture("testball-0.1-patches.tgz")}"
          sha256 tarball_fixture_sha256("testball-0.1-patches.tgz")
          apply "noop-a.diff"
        end
      end,
    ).to be_patched
  end

  specify "single_patch_dsl_with_sequential_apply" do
    expect(
      formula do
        T.bind(self, T.class_of(Formula))
        patch do
          url "file://#{tarball_fixture("testball-0.1-patches.tgz")}"
          sha256 tarball_fixture_sha256("testball-0.1-patches.tgz")
          apply "noop-a.diff", "noop-c.diff"
        end
      end,
    ).to be_sequentially_patched
  end

  specify "single_patch_dsl_with_strip" do
    expect(
      formula do
        T.bind(self, T.class_of(Formula))
        patch :p1 do
          url "file://#{patch_fixture("noop-a")}"
          sha256 patch_fixture_sha256("noop-a")
        end
      end,
    ).to be_patched
  end

  specify "single_patch_dsl_with_strip_with_apply" do
    external_patch = formula do
      T.bind(self, T.class_of(Formula))
      patch :p1 do
        url "file://#{tarball_fixture("testball-0.1-patches.tgz")}"
        sha256 tarball_fixture_sha256("testball-0.1-patches.tgz")
        apply "noop-a.diff"
      end
    end.stable.patches.last

    expect(external_patch).to have_attributes(strip: :p1, patch_files: ["noop-a.diff"])
    external_patch.fetch
    external_patch.resource.unpack do
      expect(Pathname.pwd/external_patch.patch_files.fetch(0)).to be_a_file
    end
  end

  specify "single_patch_dsl_with_incorrect_strip" do
    expect do
      f = formula do
        T.bind(self, T.class_of(Formula))
        patch :p0 do
          url "file://#{patch_fixture("noop-a")}"
          sha256 patch_fixture_sha256("noop-a")
        end
      end

      f.brew { |formula, _staging| formula.patch }
    end.to raise_error(BuildError)
  end

  specify "single_patch_dsl_with_incorrect_strip_with_apply" do
    expect do
      f = formula do
        T.bind(self, T.class_of(Formula))
        patch :p0 do
          url "file://#{tarball_fixture("testball-0.1-patches.tgz")}"
          sha256 tarball_fixture_sha256("testball-0.1-patches.tgz")
          apply "noop-a.diff"
        end
      end

      f.brew { |formula, _staging| formula.patch }
    end.to raise_error(BuildError)
  end

  specify "patch_p0_dsl" do
    expect(
      formula do
        T.bind(self, T.class_of(Formula))
        patch :p0 do
          url "file://#{patch_fixture("noop-b")}"
          sha256 patch_fixture_sha256("noop-b")
        end
      end,
    ).to be_patched
  end

  specify "patch_p0_dsl_with_apply" do
    expect(
      formula do
        T.bind(self, T.class_of(Formula))
        patch :p0 do
          url "file://#{tarball_fixture("testball-0.1-patches.tgz")}"
          sha256 tarball_fixture_sha256("testball-0.1-patches.tgz")
          apply "noop-b.diff"
        end
      end,
    ).to be_patched
  end

  specify "patch_string" do
    expect(
      formula do
        T.bind(self, T.class_of(Formula))
        patch File.read(patch_fixture("noop-a"))
      end,
    ).to be_patched
  end

  specify "patch_string_with_strip" do
    expect(
      formula do
        T.bind(self, T.class_of(Formula))
        patch :p0, File.read(patch_fixture("noop-b"))
      end,
    ).to be_patched
  end

  specify "single_patch_dsl_missing_apply_fail" do
    expect(
      formula do
        T.bind(self, T.class_of(Formula))
        patch do
          url "file://#{tarball_fixture("testball-0.1-patches.tgz")}"
          sha256 tarball_fixture_sha256("testball-0.1-patches.tgz")
        end
      end,
    ).to miss_apply
  end

  specify "single_patch_dsl_with_apply_enoent_fail" do
    expect do
      f = formula do
        T.bind(self, T.class_of(Formula))
        patch do
          url "file://#{tarball_fixture("testball-0.1-patches.tgz")}"
          sha256 tarball_fixture_sha256("testball-0.1-patches.tgz")
          apply "patches/noop-a.diff"
        end
      end

      f.brew { |formula, _staging| formula.patch }
    end.to raise_error(Errno::ENOENT)
  end

  specify "patch_dsl_with_homebrew_prefix" do
    expect(
      formula do
        T.bind(self, T.class_of(Formula))
        patch do
          url "file://#{patch_fixture("noop-d")}"
          sha256 patch_fixture_sha256("noop-d")
        end
      end,
    ).to be_patched_with_homebrew_prefix
  end
end
