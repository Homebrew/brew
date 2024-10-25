# frozen_string_literal: true

require "formula"

RSpec.describe "patching", type: :system do
  let(:formula_subclass) do
    Class.new(Formula) do
      # These are defined within an anonymous class to avoid polluting the global namespace.
      # rubocop:disable RSpec/LeakyConstantDeclaration,Lint/ConstantDefinitionInBlock
      TESTBALL_URL = "file://#{TEST_FIXTURE_DIR}/tarballs/testball-0.1.tbz".freeze
      TESTBALL_PATCHES_URL = "file://#{TEST_FIXTURE_DIR}/tarballs/testball-0.1-patches.tgz".freeze
      PATCH_URL_A = "file://#{TEST_FIXTURE_DIR}/patches/noop-a.diff".freeze
      PATCH_URL_B = "file://#{TEST_FIXTURE_DIR}/patches/noop-b.diff".freeze
      PATCH_URL_D = "file://#{TEST_FIXTURE_DIR}/patches/noop-d.diff".freeze
      PATCH_A_CONTENTS = File.read("#{TEST_FIXTURE_DIR}/patches/noop-a.diff").freeze
      PATCH_B_CONTENTS = File.read("#{TEST_FIXTURE_DIR}/patches/noop-b.diff").freeze
      APPLY_A = "noop-a.diff"
      APPLY_B = "noop-b.diff"
      APPLY_C = "noop-c.diff"
      APPLY_D = "noop-d.diff"
      # rubocop:enable RSpec/LeakyConstantDeclaration,Lint/ConstantDefinitionInBlock

      url TESTBALL_URL
      sha256 TESTBALL_SHA256
    end
  end

  def formula(name = "formula_name", path: Formulary.core_path(name), spec: :stable, alias_path: nil, &block)
    formula_subclass.class_eval(&block)
    formula_subclass.new(name, path, spec, alias_path:)
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
        patch do
          url PATCH_URL_A
          sha256 PATCH_A_SHA256
        end
      end,
    ).to be_patched
  end

  specify "single_patch_dsl_for_resource" do
    expect(
      formula do
        resource "some_resource" do
          url TESTBALL_URL
          sha256 TESTBALL_SHA256

          patch do
            url PATCH_URL_A
            sha256 PATCH_A_SHA256
          end
        end
      end,
    ).to have_its_resource_patched
  end

  specify "single_patch_dsl_with_apply" do
    expect(
      formula do
        patch do
          url TESTBALL_PATCHES_URL
          sha256 TESTBALL_PATCHES_SHA256
          apply APPLY_A
        end
      end,
    ).to be_patched
  end

  specify "single_patch_dsl_with_sequential_apply" do
    expect(
      formula do
        patch do
          url TESTBALL_PATCHES_URL
          sha256 TESTBALL_PATCHES_SHA256
          apply APPLY_A, APPLY_C
        end
      end,
    ).to be_sequentially_patched
  end

  specify "single_patch_dsl_with_strip" do
    expect(
      formula do
        patch :p1 do
          url PATCH_URL_A
          sha256 PATCH_A_SHA256
        end
      end,
    ).to be_patched
  end

  specify "single_patch_dsl_with_strip_with_apply" do
    expect(
      formula do
        patch :p1 do
          url TESTBALL_PATCHES_URL
          sha256 TESTBALL_PATCHES_SHA256
          apply APPLY_A
        end
      end,
    ).to be_patched
  end

  specify "single_patch_dsl_with_incorrect_strip" do
    expect do
      f = formula do
        patch :p0 do
          url PATCH_URL_A
          sha256 PATCH_A_SHA256
        end
      end

      f.brew { |formula, _staging| formula.patch }
    end.to raise_error(BuildError)
  end

  specify "single_patch_dsl_with_incorrect_strip_with_apply" do
    expect do
      f = formula do
        patch :p0 do
          url TESTBALL_PATCHES_URL
          sha256 TESTBALL_PATCHES_SHA256
          apply APPLY_A
        end
      end

      f.brew { |formula, _staging| formula.patch }
    end.to raise_error(BuildError)
  end

  specify "patch_p0_dsl" do
    expect(
      formula do
        patch :p0 do
          url PATCH_URL_B
          sha256 PATCH_B_SHA256
        end
      end,
    ).to be_patched
  end

  specify "patch_p0_dsl_with_apply" do
    expect(
      formula do
        patch :p0 do
          url TESTBALL_PATCHES_URL
          sha256 TESTBALL_PATCHES_SHA256
          apply APPLY_B
        end
      end,
    ).to be_patched
  end

  specify "patch_string" do
    expect(formula { patch PATCH_A_CONTENTS }).to be_patched
  end

  specify "patch_string_with_strip" do
    expect(formula { patch :p0, PATCH_B_CONTENTS }).to be_patched
  end

  specify "single_patch_dsl_missing_apply_fail" do
    expect(
      formula do
        patch do
          url TESTBALL_PATCHES_URL
          sha256 TESTBALL_PATCHES_SHA256
        end
      end,
    ).to miss_apply
  end

  specify "single_patch_dsl_with_apply_enoent_fail" do
    expect do
      f = formula do
        patch do
          url TESTBALL_PATCHES_URL
          sha256 TESTBALL_PATCHES_SHA256
          apply "patches/#{APPLY_A}"
        end
      end

      f.brew { |formula, _staging| formula.patch }
    end.to raise_error(Errno::ENOENT)
  end

  specify "patch_dsl_with_homebrew_prefix" do
    expect(
      formula do
        patch do
          url PATCH_URL_D
          sha256 PATCH_D_SHA256
        end
      end,
    ).to be_patched_with_homebrew_prefix
  end
end
