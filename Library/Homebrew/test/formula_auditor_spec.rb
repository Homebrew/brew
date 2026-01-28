# frozen_string_literal: true

require "formula_auditor"
require "git_repository"
require "securerandom"

RSpec.describe Homebrew::FormulaAuditor do
  include FileUtils
  include Test::Helper::Formula

  let(:dir) { mktmpdir }
  let(:foo_version) do
    @count ||= 0
    @count += 1
  end
  let(:formula_subpath) { "Formula/foo#{foo_version}.rb" }
  let(:origin_tap_path) { HOMEBREW_TAP_DIRECTORY/"homebrew/homebrew-foo" }
  let(:origin_formula_path) { origin_tap_path/formula_subpath }
  let(:tap_path) { HOMEBREW_TAP_DIRECTORY/"homebrew/homebrew-bar" }
  let(:formula_path) { tap_path/formula_subpath }

  def formula_auditor(name, text, options = {})
    path = Pathname.new "#{dir}/#{name}.rb"
    path.open("w") do |f|
      f.write text
    end

    formula = Formulary.factory(path)

    if options.key? :tap_audit_exceptions
      tap = Tap.fetch("test/tap")
      allow(tap).to receive(:audit_exceptions).and_return(options[:tap_audit_exceptions])
      allow(formula).to receive(:tap).and_return(tap)
      options.delete :tap_audit_exceptions
    end

    described_class.new(formula, options)
  end

  def formula_gsub(before, after = "")
    text = formula_path.read
    text.gsub! before, after
    formula_path.unlink
    formula_path.write text
  end

  def test_formula_source(name:, compatibility_version: nil, revision: 0, depends_on: [])
    class_name = name.gsub(/[^0-9a-z]/i, "_").split("_").reject(&:empty?).map(&:capitalize).join
    class_name = "TestFormula#{SecureRandom.hex(2)}" if class_name.empty?

    lines = []
    lines << "class #{class_name} < Formula"
    lines << '  desc "Test formula"'
    lines << '  homepage "https://brew.sh"'
    lines << %Q(  url "https://brew.sh/#{name}-1.0.tar.gz")
    lines << '  sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"'
    lines << "  compatibility_version #{compatibility_version}" if compatibility_version
    lines << "  revision #{revision}" if revision.positive?
    Array(depends_on).each { |dep| lines << %Q(  depends_on "#{dep}") }
    lines << "  def install"
    lines << "    bin.mkpath"
    lines << "  end"
    lines << "end"
    "#{lines.join("\n")}\n"
  end

  def formula_gsub_origin_commit(before, after = "")
    text = origin_formula_path.read
    text.gsub!(before, after)
    origin_formula_path.unlink
    origin_formula_path.write text

    origin_tap_path.cd do
      system "git", "commit", "-am", "commit"
    end

    tap_path.cd do
      system "git", "fetch"
      system "git", "reset", "--hard", "origin/HEAD"
    end
  end

  describe "#problems" do
    it "is empty by default" do
      fa = formula_auditor "foo", <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY

      expect(fa.problems).to be_empty
    end
  end

  describe "#audit_license" do
    let(:spdx_license_data) { SPDX.license_data }
    let(:spdx_exception_data) { SPDX.exception_data }

    let(:deprecated_spdx_id) { "GPL-1.0" }
    let(:license_all_custom_id) { 'all_of: ["MIT", "zzz"]' }
    let(:deprecated_spdx_exception) { "Nokia-Qt-exception-1.1" }
    let(:license_any) { 'any_of: ["0BSD", "GPL-3.0-only"]' }
    let(:license_any_with_plus) { 'any_of: ["0BSD+", "GPL-3.0-only"]' }
    let(:license_nested_conditions) { 'any_of: ["0BSD", { all_of: ["GPL-3.0-only", "MIT"] }]' }
    let(:license_any_mismatch) { 'any_of: ["0BSD", "MIT"]' }
    let(:license_any_nonstandard) { 'any_of: ["0BSD", "zzz", "MIT"]' }
    let(:license_any_deprecated) { 'any_of: ["0BSD", "GPL-1.0", "MIT"]' }

    it "does not check if the formula is not a new formula" do
      fa = formula_auditor "foo", <<~RUBY, new_formula: false
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY

      fa.audit_license
      expect(fa.problems).to be_empty
    end

    it "detects no license info" do
      fa = formula_auditor "foo", <<~RUBY, spdx_license_data:, new_formula: true, core_tap: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY

      fa.audit_license
      expect(fa.problems.first[:message]).to match "Formulae in homebrew/core must specify a license."
    end

    it "detects if license is not a standard spdx-id" do
      fa = formula_auditor "foo", <<~RUBY, spdx_license_data:, new_formula: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          license "zzz"
        end
      RUBY

      fa.audit_license
      expect(fa.problems.first[:message]).to match <<~EOS
        Formula foo contains non-standard SPDX licenses: ["zzz"].
        For a list of valid licenses check: https://spdx.org/licenses/
      EOS
    end

    it "detects if license is a deprecated spdx-id" do
      fa = formula_auditor "foo", <<~RUBY, spdx_license_data:, new_formula: true, strict: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          license "#{deprecated_spdx_id}"
        end
      RUBY

      fa.audit_license
      expect(fa.problems.first[:message]).to eq <<~EOS
        Formula foo contains deprecated SPDX licenses: ["GPL-1.0"].
        You may need to add `-only` or `-or-later` for GNU licenses (e.g. `GPL`, `LGPL`, `AGPL`, `GFDL`).
        For a list of valid licenses check: https://spdx.org/licenses/
      EOS
    end

    it "detects if license with AND contains a non-standard spdx-id" do
      fa = formula_auditor "foo", <<~RUBY, spdx_license_data:, new_formula: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          license #{license_all_custom_id}
        end
      RUBY

      fa.audit_license
      expect(fa.problems.first[:message]).to match <<~EOS
        Formula foo contains non-standard SPDX licenses: ["zzz"].
        For a list of valid licenses check: https://spdx.org/licenses/
      EOS
    end

    it "detects if license array contains a non-standard spdx-id" do
      fa = formula_auditor "foo", <<~RUBY, spdx_license_data:, new_formula: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          license #{license_any_nonstandard}
        end
      RUBY

      fa.audit_license
      expect(fa.problems.first[:message]).to match <<~EOS
        Formula foo contains non-standard SPDX licenses: ["zzz"].
        For a list of valid licenses check: https://spdx.org/licenses/
      EOS
    end

    it "detects if license array contains a deprecated spdx-id" do
      fa = formula_auditor "foo", <<~RUBY, spdx_license_data:, new_formula: true, strict: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          license #{license_any_deprecated}
        end
      RUBY

      fa.audit_license
      expect(fa.problems.first[:message]).to eq <<~EOS
        Formula foo contains deprecated SPDX licenses: ["GPL-1.0"].
        You may need to add `-only` or `-or-later` for GNU licenses (e.g. `GPL`, `LGPL`, `AGPL`, `GFDL`).
        For a list of valid licenses check: https://spdx.org/licenses/
      EOS
    end

    it "verifies that a license info is a standard spdx id" do
      fa = formula_auditor "foo", <<~RUBY, spdx_license_data:, new_formula: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          license "0BSD"
        end
      RUBY

      fa.audit_license
      expect(fa.problems).to be_empty
    end

    it "verifies that a license info with plus is a standard spdx id" do
      fa = formula_auditor "foo", <<~RUBY, spdx_license_data:, new_formula: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          license "0BSD+"
        end
      RUBY

      fa.audit_license
      expect(fa.problems).to be_empty
    end

    it "allows :public_domain license" do
      fa = formula_auditor "foo", <<~RUBY, spdx_license_data:, new_formula: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          license :public_domain
        end
      RUBY

      fa.audit_license
      expect(fa.problems).to be_empty
    end

    it "verifies that a license info with multiple licenses are standard spdx ids" do
      fa = formula_auditor "foo", <<~RUBY, spdx_license_data:, new_formula: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          license any_of: ["0BSD", "MIT"]
        end
      RUBY

      fa.audit_license
      expect(fa.problems).to be_empty
    end

    it "verifies that a license info with exceptions are standard spdx ids" do
      formula_text = <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          license "Apache-2.0" => { with: "LLVM-exception" }
        end
      RUBY
      fa = formula_auditor("foo", formula_text, new_formula: true,
                           spdx_license_data:, spdx_exception_data:)

      fa.audit_license
      expect(fa.problems).to be_empty
    end

    it "verifies that a license array contains only standard spdx id" do
      fa = formula_auditor "foo", <<~RUBY, spdx_license_data:, new_formula: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          license #{license_any}
        end
      RUBY

      fa.audit_license
      expect(fa.problems).to be_empty
    end

    it "verifies that a license array contains only standard spdx id with plus" do
      fa = formula_auditor "foo", <<~RUBY, spdx_license_data:, new_formula: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          license #{license_any_with_plus}
        end
      RUBY

      fa.audit_license
      expect(fa.problems).to be_empty
    end

    it "verifies that a license array with AND contains only standard spdx ids" do
      fa = formula_auditor "foo", <<~RUBY, spdx_license_data:, new_formula: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          license #{license_nested_conditions}
        end
      RUBY

      fa.audit_license
      expect(fa.problems).to be_empty
    end

    it "checks online and verifies that a standard license id is the same " \
       "as what is indicated on its GitHub repo", :needs_network do
      formula_text = <<~RUBY
        class Cask < Formula
          url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
          head "https://github.com/cask/cask.git", branch: "main"
          license "GPL-3.0-or-later"
        end
      RUBY
      fa = formula_auditor "cask", formula_text, spdx_license_data:,
                           online: true, core_tap: true, new_formula: true

      fa.audit_license
      expect(fa.problems).to be_empty
    end

    it "checks online and verifies that a standard license id with AND is the same " \
       "as what is indicated on its GitHub repo", :needs_network do
      formula_text = <<~RUBY
        class Cask < Formula
          url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
          head "https://github.com/cask/cask.git", branch: "main"
          license all_of: ["GPL-3.0-or-later", "MIT"]
        end
      RUBY
      fa = formula_auditor "cask", formula_text, spdx_license_data:,
                           online: true, core_tap: true, new_formula: true

      fa.audit_license
      expect(fa.problems).to be_empty
    end

    it "checks online and verifies that a standard license id with WITH is the same " \
       "as what is indicated on its GitHub repo", :needs_network do
      formula_text = <<~RUBY
        class Cask < Formula
          url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
          head "https://github.com/cask/cask.git", branch: "main"
          license "GPL-3.0-or-later" => { with: "LLVM-exception" }
        end
      RUBY
      fa = formula_auditor("cask", formula_text, online: true, core_tap: true, new_formula: true,
                           spdx_license_data:, spdx_exception_data:)

      fa.audit_license
      expect(fa.problems).to be_empty
    end

    it "verifies that a license exception has standard spdx ids", :needs_network do
      formula_text = <<~RUBY
        class Cask < Formula
          url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
          head "https://github.com/cask/cask.git", branch: "main"
          license "GPL-3.0-or-later" => { with: "zzz" }
        end
      RUBY
      fa = formula_auditor("cask", formula_text, core_tap: true, new_formula: true,
                           spdx_license_data:, spdx_exception_data:)

      fa.audit_license
      expect(fa.problems.first[:message]).to match <<~EOS
        Formula cask contains invalid or deprecated SPDX license exceptions: ["zzz"].
        For a list of valid license exceptions check:
          https://spdx.org/licenses/exceptions-index.html
      EOS
    end

    it "verifies that a license exception has non-deprecated spdx ids", :needs_network do
      formula_text = <<~RUBY
        class Cask < Formula
          url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
          head "https://github.com/cask/cask.git", branch: "main"
          license "GPL-3.0-or-later" => { with: "#{deprecated_spdx_exception}" }
        end
      RUBY
      fa = formula_auditor("cask", formula_text, core_tap: true, new_formula: true,
                           spdx_license_data:, spdx_exception_data:)

      fa.audit_license
      expect(fa.problems.first[:message]).to match <<~EOS
        Formula cask contains invalid or deprecated SPDX license exceptions: ["#{deprecated_spdx_exception}"].
        For a list of valid license exceptions check:
          https://spdx.org/licenses/exceptions-index.html
      EOS
    end

    it "checks online and verifies that a standard license id is in the same exempted license group " \
       "as what is indicated on its GitHub repo", :needs_network do
      fa = formula_auditor "cask", <<~RUBY, spdx_license_data:, online: true, new_formula: true
        class Cask < Formula
          url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
          head "https://github.com/cask/cask.git", branch: "main"
          license "GPL-3.0-or-later"
        end
      RUBY

      fa.audit_license
      expect(fa.problems).to be_empty
    end

    it "checks online and verifies that a standard license array is in the same exempted license group " \
       "as what is indicated on its GitHub repo", :needs_network do
      fa = formula_auditor "cask", <<~RUBY, spdx_license_data:, online: true, new_formula: true
        class Cask < Formula
          url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
          head "https://github.com/cask/cask.git", branch: "main"
          license any_of: ["GPL-3.0-or-later", "MIT"]
        end
      RUBY

      fa.audit_license
      expect(fa.problems).to be_empty
    end

    it "checks online and detects that a formula-specified license is not " \
       "the same as what is indicated on its GitHub repository", :needs_network do
      formula_text = <<~RUBY
        class Cask < Formula
          url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
          head "https://github.com/cask/cask.git", branch: "main"
          license "0BSD"
        end
      RUBY
      fa = formula_auditor "cask", formula_text, spdx_license_data:,
                           online: true, core_tap: true, new_formula: true

      fa.audit_license
      expect(fa.problems.first[:message])
        .to eq 'Formula license ["0BSD"] does not match GitHub license ["GPL-3.0"].'
    end

    it "allows a formula-specified license that differs from its GitHub " \
       "repository for formulae on the mismatched license allowlist", :needs_network do
      formula_text = <<~RUBY
        class Cask < Formula
          url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
          head "https://github.com/cask/cask.git", branch: "main"
          license "0BSD"
        end
      RUBY
      fa = formula_auditor "cask", formula_text, spdx_license_data:,
                           online: true, core_tap: true, new_formula: true,
                           tap_audit_exceptions: { permitted_formula_license_mismatches: ["cask"] }

      fa.audit_license
      expect(fa.problems).to be_empty
    end

    it "checks online and detects that an array of license does not contain " \
       "what is indicated on its GitHub repository", :needs_network do
      formula_text = <<~RUBY
        class Cask < Formula
          url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
          head "https://github.com/cask/cask.git", branch: "main"
          license #{license_any_mismatch}
        end
      RUBY
      fa = formula_auditor "cask", formula_text, spdx_license_data:,
                           online: true, core_tap: true, new_formula: true

      fa.audit_license
      expect(fa.problems.first[:message]).to match "Formula license [\"0BSD\", \"MIT\"] " \
                                                   "does not match GitHub license [\"GPL-3.0\"]."
    end

    it "checks online and verifies that an array of license contains " \
       "what is indicated on its GitHub repository", :needs_network do
      formula_text = <<~RUBY
        class Cask < Formula
          url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
          head "https://github.com/cask/cask.git", branch: "main"
          license #{license_any}
        end
      RUBY
      fa = formula_auditor "cask", formula_text, spdx_license_data:,
                           online: true, core_tap: true, new_formula: true

      fa.audit_license
      expect(fa.problems).to be_empty
    end
  end

  describe "#audit_file" do
    specify "no issue" do
      fa = formula_auditor "foo", <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"
        end
      RUBY

      fa.audit_file
      expect(fa.problems).to be_empty
    end
  end

  describe "#audit_name" do
    specify "no issue" do
      fa = formula_auditor "foo", <<~RUBY, core_tap: true, strict: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"
        end
      RUBY

      fa.audit_name
      expect(fa.problems).to be_empty
    end

    specify "uppercase formula name" do
      fa = formula_auditor "Foo", <<~RUBY
        class Foo < Formula
          url "https://brew.sh/Foo-1.0.tgz"
          homepage "https://brew.sh"
        end
      RUBY

      fa.audit_name
      expect(fa.problems.first[:message]).to match "must not contain uppercase letters"
    end
  end

  describe "#audit_resource_name_matches_pypi_package_name_in_url" do
    it "reports a problem if the resource name does not match the python sdist name" do
      fa = formula_auditor "foo", <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          sha256 "abc123"
          homepage "https://brew.sh"

          resource "Something" do
            url "https://files.pythonhosted.org/packages/FooSomething-1.0.0.tar.gz"
            sha256 "def456"
          end
        end
      RUBY

      fa.audit_specs
      expect(fa.problems.first[:message])
        .to match("`resource` name should be 'FooSomething' to match the PyPI package name")
    end

    it "reports a problem if the resource name does not match the python wheel name" do
      fa = formula_auditor "foo", <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          sha256 "abc123"
          homepage "https://brew.sh"

          resource "Something" do
            url "https://files.pythonhosted.org/packages/FooSomething-1.0.0-py3-none-any.whl"
            sha256 "def456"
          end
        end
      RUBY

      fa.audit_specs
      expect(fa.problems.first[:message])
        .to match("`resource` name should be 'FooSomething' to match the PyPI package name")
    end
  end

  describe "#check_service_command" do
    specify "Not installed" do
      fa = formula_auditor "foo", <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          service do
            run []
          end
        end
      RUBY

      expect(fa.check_service_command(fa.formula)).to match nil
    end

    specify "No service" do
      fa = formula_auditor "foo", <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"
        end
      RUBY

      mkdir_p fa.formula.prefix
      expect(fa.check_service_command(fa.formula)).to match nil
    end

    specify "No command" do
      fa = formula_auditor "foo", <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          service do
            run []
          end
        end
      RUBY

      mkdir_p fa.formula.prefix
      expect(fa.check_service_command(fa.formula)).to match nil
    end

    specify "Invalid command" do
      fa = formula_auditor "foo", <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          service do
            run [HOMEBREW_PREFIX/"bin/something"]
          end
        end
      RUBY

      mkdir_p fa.formula.prefix
      expect(fa.check_service_command(fa.formula)).to match "Service command does not exist"
    end
  end

  describe "#audit_github_repository" do
    specify "#audit_github_repository when HOMEBREW_NO_GITHUB_API is set" do
      ENV["HOMEBREW_NO_GITHUB_API"] = "1"

      fa = formula_auditor "foo", <<~RUBY, strict: true, online: true
        class Foo < Formula
          homepage "https://github.com/example/example"
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY

      fa.audit_github_repository
      expect(fa.problems).to be_empty
    end
  end

  describe "#audit_github_repository_archived" do
    specify "#audit_github_repository_archived when HOMEBREW_NO_GITHUB_API is set" do
      fa = formula_auditor "foo", <<~RUBY, strict: true, online: true
        class Foo < Formula
          homepage "https://github.com/example/example"
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY

      fa.audit_github_repository_archived
      expect(fa.problems).to be_empty
    end
  end

  describe "#audit_gitlab_repository" do
    specify "#audit_gitlab_repository for stars, forks and creation date" do
      fa = formula_auditor "foo", <<~RUBY, strict: true, online: true
        class Foo < Formula
          homepage "https://gitlab.com/libtiff/libtiff"
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY

      fa.audit_gitlab_repository
      expect(fa.problems).to be_empty
    end
  end

  describe "#audit_gitlab_repository_archived" do
    specify "#audit gitlab repository for archived status" do
      fa = formula_auditor "foo", <<~RUBY, strict: true, online: true
        class Foo < Formula
          homepage "https://gitlab.com/libtiff/libtiff"
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY

      fa.audit_gitlab_repository_archived
      expect(fa.problems).to be_empty
    end
  end

  describe "#audit_bitbucket_repository" do
    specify "#audit_bitbucket_repository for stars, forks and creation date" do
      fa = formula_auditor "foo", <<~RUBY, strict: true, online: true
        class Foo < Formula
          homepage "https://bitbucket.com/libtiff/libtiff"
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY

      fa.audit_bitbucket_repository
      expect(fa.problems).to be_empty
    end
  end

  describe "#audit_specs" do
    let(:livecheck_throttle) { "livecheck do\n    throttle 10\n  end" }
    let(:versioned_head_spec_list) { { versioned_head_spec_allowlist: ["foo"] } }

    it "doesn't allow to miss a checksum" do
      fa = formula_auditor "foo", <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY

      fa.audit_specs
      expect(fa.problems.first[:message]).to match "Checksum is missing"
    end

    it "allows to miss a checksum for git strategy" do
      fa = formula_auditor "foo", <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo.git", tag: "1.0", revision: "f5e00e485e7aa4c5baa20355b27e3b84a6912790"
        end
      RUBY

      fa.audit_specs
      expect(fa.problems).to be_empty
    end

    it "allows to miss a checksum for HEAD" do
      fa = formula_auditor "foo", <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          head "https://brew.sh/foo.tgz"
        end
      RUBY

      fa.audit_specs
      expect(fa.problems).to be_empty
    end

    it "requires `branch:` to be specified for Git head URLs" do
      fa = formula_auditor "foo", <<~RUBY, online: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          head "https://github.com/Homebrew/homebrew-test-bot.git"
        end
      RUBY

      fa.audit_specs
      # This is `.last` because the first problem is the unreachable stable URL.
      expect(fa.problems.last[:message]).to match("Git `head` URL must specify a branch name")
    end

    it "suggests a detected default branch for Git head URLs" do
      fa = formula_auditor "foo", <<~RUBY, online: true, core_tap: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          head "https://github.com/Homebrew/homebrew-test-bot.git", branch: "master"
        end
      RUBY

      message = "To use a non-default HEAD branch, add the formula to `head_non_default_branch_allowlist.json`."
      fa.audit_specs
      # This is `.last` because the first problem is the unreachable stable URL.
      expect(fa.problems.last[:message]).to match(message)
    end

    it "can specify a default branch without an allowlist if not in a core tap" do
      fa = formula_auditor "foo", <<~RUBY, online: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          head "https://github.com/Homebrew/homebrew-test-bot.git", branch: "main"
        end
      RUBY

      fa.audit_specs
      expect(fa.problems).not_to match("Git `head` URL must specify a branch name")
    end

    it "ignores `branch:` for non-Git head URLs" do
      fa = formula_auditor "foo", <<~RUBY, online: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          head "https://brew.sh/foo.tgz", branch: "develop"
        end
      RUBY

      fa.audit_specs
      expect(fa.problems).not_to match("Git `head` URL must specify a branch name")
    end

    it "ignores `branch:` for `resource` URLs" do
      fa = formula_auditor "foo", <<~RUBY, online: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"

          resource "bar" do
            url "https://raw.githubusercontent.com/Homebrew/homebrew-core/HEAD/Formula/bar.rb"
            sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          end
        end
      RUBY

      fa.audit_specs
      expect(fa.problems).not_to match("Git `head` URL must specify a branch name")
    end

    it "allows versions with no throttle rate" do
      fa = formula_auditor "bar", <<~RUBY, core_tap: true
        class Bar < Formula
          url "https://brew.sh/foo-1.0.1.tgz"
          sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
        end
      RUBY

      fa.audit_specs
      expect(fa.problems).to be_empty
    end

    it "allows major/minor versions with throttle rate" do
      fa = formula_auditor "foo", <<~RUBY, core_tap: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.0.tgz"
          sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          #{livecheck_throttle}
        end
      RUBY

      fa.audit_specs
      expect(fa.problems).to be_empty
    end

    it "allows patch versions to be multiples of the throttle rate" do
      fa = formula_auditor "foo", <<~RUBY, core_tap: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.10.tgz"
          sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          #{livecheck_throttle}
        end
      RUBY

      fa.audit_specs
      expect(fa.problems).to be_empty
    end

    it "doesn't allow patch versions that aren't multiples of the throttle rate" do
      fa = formula_auditor "foo", <<~RUBY, core_tap: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.1.tgz"
          sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          #{livecheck_throttle}
        end
      RUBY

      fa.audit_specs
      expect(fa.problems.first[:message]).to match "Should only be updated every 10 releases on multiples of 10"
    end

    it "allows non-versioned formulae to have a `HEAD` spec" do
      fa = formula_auditor "bar", <<~RUBY, core_tap: true, tap_audit_exceptions: versioned_head_spec_list
        class Bar < Formula
          url "https://brew.sh/foo-1.0.tgz"
          sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          head "https://brew.sh/foo.git", branch: "develop"
        end
      RUBY

      fa.audit_specs
      expect(fa.problems).to be_empty
    end

    it "doesn't allow versioned formulae to have a `HEAD` spec" do
      fa = formula_auditor "bar@1", <<~RUBY, core_tap: true, tap_audit_exceptions: versioned_head_spec_list
        class BarAT1 < Formula
          url "https://brew.sh/foo-1.0.tgz"
          sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          head "https://brew.sh/foo.git", branch: "develop"
        end
      RUBY

      fa.audit_specs
      expect(fa.problems.first[:message]).to match "Versioned formulae should not have a `head` spec"
    end

    it "allows versioned formulae on the allowlist to have a `HEAD` spec" do
      fa = formula_auditor "foo", <<~RUBY, core_tap: true, tap_audit_exceptions: versioned_head_spec_list
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          head "https://brew.sh/foo.git", branch: "develop"
        end
      RUBY

      fa.audit_specs
      expect(fa.problems).to be_empty
    end
  end

  describe "#audit_deps" do
    describe "a dependency on a macOS-provided keg-only formula" do
      describe "which is allowlisted" do
        subject(:f_a) { fa }

        let(:fa) do
          formula_auditor "foo", <<~RUBY, new_formula: true
            class Foo < Formula
              url "https://brew.sh/foo-1.0.tgz"
              homepage "https://brew.sh"

              depends_on "openssl"
            end
          RUBY
        end

        let(:f_openssl) do
          formula do
            url "https://brew.sh/openssl-1.0.tgz"
            homepage "https://brew.sh"

            keg_only :provided_by_macos
          end
        end

        before do
          allow(fa.formula.deps.first)
            .to receive(:to_formula).and_return(f_openssl)
          fa.audit_deps
        end

        it(:problems) { expect(f_a.problems).to be_empty }
      end

      describe "which is not allowlisted", :needs_macos do
        subject(:f_a) { fa }

        let(:fa) do
          formula_auditor "foo", <<~RUBY, new_formula: true, core_tap: true
            class Foo < Formula
              url "https://brew.sh/foo-1.0.tgz"
              homepage "https://brew.sh"

              depends_on "bc"
            end
          RUBY
        end

        let(:f_bc) do
          formula do
            url "https://brew.sh/bc-1.0.tgz"
            homepage "https://brew.sh"

            keg_only :provided_by_macos
          end
        end

        before do
          allow(fa.formula.deps.first)
            .to receive(:to_formula).and_return(f_bc)
          fa.audit_deps
        end

        it(:new_formula_problems) do
          expect(f_a.new_formula_problems)
            .to include(a_hash_including(message: a_string_matching(/is provided by macOS/)))
        end
      end
    end

    describe "dependency tag" do
      subject(:f_a) { fa }

      let(:core_tap) { false }
      let(:fa) do
        formula_auditor "foo", <<~RUBY, core_tap:
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tgz"
            homepage "https://brew.sh"

            depends_on "bar" => #{tag.inspect}
          end
        RUBY
      end
      let(:f_bar) do
        formula do
          url "https://brew.sh/bar-1.0.tgz"
          homepage "https://brew.sh"
        end
      end

      before do
        allow(fa.formula.deps.first).to receive(:to_formula).and_return(f_bar)
        fa.audit_deps
      end

      describe ":build" do
        let(:tag) { :build }

        it(:problems) { expect(f_a.problems).to be_empty }
      end

      describe ":run" do
        let(:tag) { :run }

        it(:problems) do
          expect(f_a.problems).to include(a_hash_including(message: a_string_matching(/is a no-op/)))
        end
      end

      describe ":linked" do
        let(:tag) { :linked }

        it(:problems) do
          expect(f_a.problems).to include(a_hash_including(message: a_string_matching(/is a no-op/)))
        end
      end

      describe ":optional" do
        let(:tag) { :optional }

        it(:problems) { expect(f_a.problems).to be_empty }

        describe "in core tap" do
          let(:core_tap) { true }

          it(:problems) do
            expect(f_a.problems).to include(a_hash_including(message: a_string_matching(/should not have optional/)))
          end
        end
      end

      describe "when invalid" do
        let(:tag) { :foo }

        it(:problems) do
          expect(f_a.problems).to include(a_hash_including(message: a_string_matching(/is not a valid tag/)))
        end
      end

      describe "when undefined option" do
        let(:tag) { "with-debug" }

        it(:problems) do
          expect(f_a.problems).to include(a_hash_including(message: a_string_matching(/does not define option/)))
        end
      end

      describe "when defined option" do
        let(:tag) { "with-debug" }
        let(:f_bar) do
          formula do
            url "https://brew.sh/bar-1.0.tgz"
            homepage "https://brew.sh"
            option "with-debug"
          end
        end

        it(:problems) { expect(f_a.problems).to be_empty }
      end
    end
  end

  describe "#audit_stable_version" do
    subject do
      fa = described_class.new(Formulary.factory(formula_path), git: true)
      fa.audit_stable_version
      fa.problems.first&.fetch(:message)
    end

    # Mock tap behaviour the Formula helper expects (e.g. PyPI lookups, audit exceptions).
    before do
      origin_formula_path.dirname.mkpath
      origin_formula_path.write <<~RUBY
        class Foo#{foo_version} < Formula
          url "https://brew.sh/foo-1.0.tar.gz"
          sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          revision 2
          version_scheme 1
        end
      RUBY

      origin_tap_path.mkpath
      origin_tap_path.cd do
        system "git", "init"
        system "git", "add", "--all"
        system "git", "commit", "-m", "init"
      end

      tap_path.mkpath
      tap_path.cd do
        system "git", "clone", origin_tap_path, "."
      end
    end

    describe "versions" do
      context "when uncommitted should not decrease" do
        before { formula_gsub "foo-1.0.tar.gz", "foo-0.9.tar.gz" }

        it { is_expected.to match("Stable: version should not decrease (from 1.0 to 0.9)") }
      end

      context "when committed can decrease" do
        before do
          formula_gsub_origin_commit "revision 2"
          formula_gsub_origin_commit "foo-1.0.tar.gz", "foo-0.9.tar.gz"
        end

        it { is_expected.to be_nil }
      end

      describe "can decrease with version_scheme increased" do
        before do
          formula_gsub "revision 2"
          formula_gsub "foo-1.0.tar.gz", "foo-0.9.tar.gz"
          formula_gsub "version_scheme 1", "version_scheme 2"
        end

        it { is_expected.to be_nil }
      end
    end
  end

  describe "#audit_revision dependency relationships" do
    subject do
      fa = described_class.new(Formulary.factory(formula_path), git: true)
      fa.audit_revision
      fa.problems.first&.fetch(:message)
    end

    before do
      origin_formula_path.dirname.mkpath
      origin_formula_path.write <<~RUBY
        class Foo#{foo_version} < Formula
          url "https://brew.sh/foo-1.0.tar.gz"
          sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          revision 2
          version_scheme 1
        end
      RUBY

      origin_tap_path.mkpath
      origin_tap_path.cd do
        system "git", "init"
        system "git", "add", "--all"
        system "git", "commit", "-m", "init"
      end

      tap_path.mkpath
      tap_path.cd do
        system "git", "clone", origin_tap_path, "."
      end
    end

    describe "new formulae should not have a revision" do
      it "doesn't allow new formulae to have a revision" do
        fa = formula_auditor "foo", <<~RUBY, new_formula: true
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tgz"
            revision 1
          end
        RUBY

        fa.audit_revision

        expect(fa.new_formula_problems).to include(
          a_hash_including(message: a_string_matching(/should not define a revision/)),
        )
      end
    end

    describe "revisions" do
      describe "should not be removed when first committed above 0" do
        it { is_expected.to be_nil }
      end

      describe "with the same version, should not decrease" do
        before { formula_gsub_origin_commit "revision 2", "revision 1" }

        it { is_expected.to match("`revision` should not decrease (from 2 to 1)") }
      end

      describe "should not be removed with the same version" do
        before { formula_gsub_origin_commit "revision 2" }

        it { is_expected.to match("`revision` should not decrease (from 2 to 0)") }
      end

      describe "should not decrease with the same, uncommitted version" do
        before { formula_gsub "revision 2", "revision 1" }

        it { is_expected.to match("`revision` should not decrease (from 2 to 1)") }
      end

      describe "should be removed with a newer version" do
        before { formula_gsub_origin_commit "foo-1.0.tar.gz", "foo-1.1.tar.gz" }

        it { is_expected.to match("`revision 2` should be removed") }
      end

      describe "should be removed with a newer local version" do
        before { formula_gsub "foo-1.0.tar.gz", "foo-1.1.tar.gz" }

        it { is_expected.to match("`revision 2` should be removed") }
      end

      describe "should not warn on an newer version revision removal" do
        before do
          formula_gsub_origin_commit "revision 2", ""
          formula_gsub_origin_commit "foo-1.0.tar.gz", "foo-1.1.tar.gz"
        end

        it { is_expected.to be_nil }
      end

      describe "should not warn when revision from previous version matches current revision" do
        before do
          formula_gsub_origin_commit "foo-1.0.tar.gz", "foo-1.1.tar.gz"
          formula_gsub_origin_commit "revision 2", "# no revision"
          formula_gsub_origin_commit "# no revision", "revision 1"
          formula_gsub_origin_commit "revision 1", "revision 2"
        end

        it { is_expected.to be_nil }
      end

      describe "should only increment by 1 with an uncommitted version" do
        before do
          formula_gsub "foo-1.0.tar.gz", "foo-1.1.tar.gz"
          formula_gsub "revision 2", "revision 4"
        end

        it { is_expected.to match("`revision` should only increment by 1") }
      end

      describe "should not warn on past increment by more than 1" do
        before do
          formula_gsub_origin_commit "revision 2", "# no revision"
          formula_gsub_origin_commit "foo-1.0.tar.gz", "foo-1.1.tar.gz"
          formula_gsub_origin_commit "# no revision", "revision 3"
        end

        it { is_expected.to be_nil }
      end
    end
  end

  def build_formula_for_audit(tap:, tap_path:, name:, compatibility_version: nil, revision: 0, depends_on: [])
    path = tap_path/"Formula/#{name}.rb"
    path.dirname.mkpath
    path.write(test_formula_source(name:, compatibility_version:, revision:, depends_on:))

    Formulary.clear_cache
    formula = Formulary.factory(path)
    allow(formula).to receive_messages(tap:, full_name: "#{tap.name}/#{name}")

    formula
  end

  def dependency_stub(name)
    instance_double(Dependency, name:)
  end

  def stub_committed_info(auditor, default:, overrides: {})
    allow(auditor).to receive(:committed_version_info) do |*_args, **kwargs|
      formula = kwargs.fetch(:formula, auditor.formula)
      raw = overrides.fetch(formula, default)
      committed = raw.map { |info| info ? info.dup : {} }
      committed.each do |info|
        info[:version] ||= formula.stable&.version
        info[:revision] = info.fetch(:revision, formula.revision)
        info[:compatibility_version] = info.fetch(:compatibility_version, formula.compatibility_version)
        info[:version_scheme] = info.fetch(:version_scheme, formula.version_scheme)
      end
      committed.each(&:compact!)
      committed
    end
  end

  def stub_changed_paths(auditor, all_paths:, filtered_paths: all_paths)
    allow(auditor).to receive(:changed_formulae_paths) do |_tap_arg, only_names: nil|
      only_names ? filtered_paths : all_paths
    end
  end

  describe "#audit_compatibility_version" do
    let(:tap_path) { Pathname("#{dir}/compat-tap") }
    let(:tap) do
      instance_double(
        Tap,
        git?:             true,
        core_tap?:        false,
        git_repository:   instance_double(GitRepository, origin_branch_name: "main"),
        audit_exceptions: {},
        formula_renames:  {},
        path:             tap_path,
        name:             "test/tap",
      )
    end
    let(:current_compatibility_version) { 2 }
    let(:target_formula) do
      build_formula_for_audit(
        tap:,
        tap_path:,
        name:                  "foo",
        compatibility_version: current_compatibility_version,
      )
    end
    let(:auditor) { described_class.new(target_formula, git: true) }
    let(:foo_path) { tap_path/"Formula/foo.rb" }
    let(:bar_path) { tap_path/"Formula/bar.rb" }

    before do
      allow(tap).to receive_messages(formula_dir: tap_path/"Formula")
      allow(target_formula).to receive_messages(full_name: "test/tap/foo", recursive_dependencies: [])
      allow(Formulary).to receive(:factory).and_call_original
      allow(Formulary).to receive(:factory).with(foo_path).and_return(target_formula)
    end

    it "ignores formulae without a previous commit" do
      stub_committed_info(auditor, default: [{}, {}])
      stub_changed_paths(auditor, all_paths: [])

      auditor.audit_compatibility_version

      expect(auditor.problems).to be_empty
    end

    context "with existing committed compatibility_version" do
      before do
        stub_changed_paths(auditor, all_paths: [])
      end

      it "flags decreases" do
        stub_committed_info(
          auditor,
          default: [{ compatibility_version: 2 }, { compatibility_version: 2 }],
        )
        allow(target_formula).to receive(:compatibility_version).and_return(1)

        auditor.audit_compatibility_version

        expect(auditor.problems).to include(
          a_hash_including(message: a_string_matching(/should not decrease/)),
        )
      end

      it "flags increments larger than one" do
        allow(target_formula).to receive(:compatibility_version).and_return(3)
        stub_committed_info(
          auditor,
          default: [{ compatibility_version: 1 }, { compatibility_version: 1 }],
        )

        auditor.audit_compatibility_version

        expect(auditor.problems).to include(
          a_hash_including(message: a_string_matching(/should only increment by 1/)),
        )
      end

      it "allows unchanged compatibility_version" do
        allow(target_formula).to receive(:compatibility_version).and_return(1)
        stub_committed_info(
          auditor,
          default: [{ compatibility_version: 1 }, { compatibility_version: 1 }],
        )

        auditor.audit_compatibility_version

        expect(auditor.problems).to be_empty
      end
    end

    context "when compatibility_version increments by one" do
      let(:dependent_formula) do
        build_formula_for_audit(
          tap:,
          tap_path:,
          name:       "bar",
          revision:   2,
          depends_on: ["foo"],
        )
      end

      before do
        allow(dependent_formula).to receive_messages(full_name:              "test/tap/bar",
                                                     recursive_dependencies: [dependency_stub("foo")])
        allow(Formulary).to receive(:factory).with(bar_path).and_return(dependent_formula)
        stub_changed_paths(auditor, all_paths: [foo_path, bar_path])
      end

      it "flags missing dependent revision bumps" do
        stub_committed_info(
          auditor,
          default:   [{ compatibility_version: 1 }, { compatibility_version: 1 }],
          overrides: { dependent_formula => [{ revision: 2 }, { revision: 2 }] },
        )

        auditor.audit_compatibility_version

        expect(auditor.problems).to include(
          a_hash_including(message: a_string_matching(/no recursive dependent formulae increased `revision` by 1/)),
        )
      end

      it "accepts a dependent revision bump" do
        stub_committed_info(
          auditor,
          default:   [{ compatibility_version: 1 }, { compatibility_version: 1 }],
          overrides: { dependent_formula => [{ revision: 1 }, { revision: 1 }] },
        )

        auditor.audit_compatibility_version

        expect(auditor.problems).to be_empty
      end
    end
  end

  describe "#audit_revision" do
    let(:tap_path) { Pathname("#{dir}/revision-tap") }
    let(:tap) do
      instance_double(
        Tap,
        git?:             true,
        core_tap?:        true,
        git_repository:   instance_double(GitRepository, origin_branch_name: "main"),
        audit_exceptions: {},
        formula_renames:  {},
        path:             tap_path,
        name:             "test/tap",
      )
    end
    let(:current_revision) { 2 }
    let(:dependency_names) { ["foo"] }
    let(:dependency_list) { dependency_names.map { |name| dependency_stub(name) } }
    let(:target_formula) do
      build_formula_for_audit(
        tap:,
        tap_path:,
        name:       "bar",
        revision:   current_revision,
        depends_on: dependency_names,
      )
    end
    let(:auditor) { described_class.new(target_formula, git: true) }
    let(:bar_path) { tap_path/"Formula/bar.rb" }
    let(:foo_path) { tap_path/"Formula/foo.rb" }
    let(:current_dependency_compatibility) { 1 }
    let(:dependency_revision) { 0 }
    let(:dependency_formula) do
      build_formula_for_audit(
        tap:,
        tap_path:,
        name:                  "foo",
        compatibility_version: current_dependency_compatibility,
        revision:              dependency_revision,
      )
    end

    before do
      allow(tap).to receive_messages(formula_dir: tap_path/"Formula")
      allow(target_formula).to receive_messages(full_name: "test/tap/bar", recursive_dependencies: dependency_list)
      allow(Formulary).to receive(:factory).and_call_original
      allow(Formulary).to receive(:factory).with(bar_path).and_return(target_formula)
      allow(Formulary).to receive(:factory).with(foo_path).and_return(dependency_formula)
    end

    it "ignores revision changes when not incremented by one" do
      stub_committed_info(
        auditor,
        default: [{ revision: current_revision }, { revision: current_revision }],
      )
      stub_changed_paths(auditor, all_paths: [], filtered_paths: [])

      auditor.audit_revision

      expect(auditor.problems).to be_empty
    end

    context "with a revision increment" do
      before do
        stub_committed_info(
          auditor,
          default: [{ revision: current_revision - 1 }, { revision: current_revision - 1 }],
        )
      end

      it "allows revision increases when there are no recursive dependencies" do
        allow(target_formula).to receive(:recursive_dependencies).and_return([])
        stub_changed_paths(auditor, all_paths: [], filtered_paths: [])

        auditor.audit_revision

        expect(auditor.problems).to be_empty
      end

      it "allows revision increases when dependencies are unchanged" do
        stub_changed_paths(auditor, all_paths: [], filtered_paths: [])

        auditor.audit_revision

        expect(auditor.problems).to be_empty
      end

      context "when dependencies change" do
        before do
          stub_changed_paths(auditor, all_paths: [foo_path], filtered_paths: [foo_path])
        end

        it "flags missing compatibility_version bumps" do
          stub_committed_info(
            auditor,
            default:   [{ revision: current_revision - 1 }, { revision: current_revision - 1 }],
            overrides: { dependency_formula => [{ compatibility_version: 1 }, { compatibility_version: 1 }] },
          )
          allow(dependency_formula).to receive(:compatibility_version).and_return(1)

          auditor.audit_revision

          expect(auditor.problems).to include(
            a_hash_including(
              message: a_string_matching(/must increase `compatibility_version` by 1: foo \(1 to 1\)/),
            ),
          )
        end

        it "accepts compatibility_version bumps of one" do
          stub_committed_info(
            auditor,
            default:   [{ revision: current_revision - 1 }, { revision: current_revision - 1 }],
            overrides: { dependency_formula => [{ compatibility_version: 1 }, { compatibility_version: 1 }] },
          )
          allow(dependency_formula).to receive(:compatibility_version).and_return(2)

          auditor.audit_revision

          expect(auditor.problems).to be_empty
        end
      end
    end
  end

  describe "#audit_versioned_keg_only" do
    specify "it warns when a versioned formula is not `keg_only`" do
      fa = formula_auditor "foo@1.1", <<~RUBY, core_tap: true
        class FooAT11 < Formula
          url "https://brew.sh/foo-1.1.tgz"
        end
      RUBY

      fa.audit_versioned_keg_only

      expect(fa.problems.first[:message])
        .to match("Versioned formulae in homebrew/core should use `keg_only :versioned_formula`")
    end

    specify "it warns when a versioned formula has an incorrect `keg_only` reason" do
      fa = formula_auditor "foo@1.1", <<~RUBY, core_tap: true
        class FooAT11 < Formula
          url "https://brew.sh/foo-1.1.tgz"

          keg_only :provided_by_macos
        end
      RUBY

      fa.audit_versioned_keg_only

      expect(fa.problems.first[:message])
        .to match("Versioned formulae in homebrew/core should use `keg_only :versioned_formula`")
    end

    specify "it does not warn when a versioned formula has `keg_only :versioned_formula`" do
      fa = formula_auditor "foo@1.1", <<~RUBY, core_tap: true
        class FooAT11 < Formula
          url "https://brew.sh/foo-1.1.tgz"

          keg_only :versioned_formula
        end
      RUBY

      fa.audit_versioned_keg_only

      expect(fa.problems).to be_empty
    end
  end

  describe "#audit_conflicts" do
    before do
      # We don't really test the formula text retrieval here
      allow(File).to receive(:open).and_return("")
    end

    specify "it warns when conflicting with non-existing formula", :no_api do
      foo = formula("foo") do
        url "https://brew.sh/bar-1.0.tgz"

        conflicts_with "bar"
      end

      fa = described_class.new foo
      fa.audit_conflicts

      expect(fa.problems.first[:message])
        .to match("Can't find conflicting formula \"bar\"")
    end

    specify "it warns when conflicting with itself", :no_api do
      foo = formula("foo") do
        url "https://brew.sh/bar-1.0.tgz"

        conflicts_with "foo"
      end
      stub_formula_loader foo

      fa = described_class.new foo
      fa.audit_conflicts

      expect(fa.problems.first[:message])
        .to match("Formula should not conflict with itself")
    end

    specify "it warns when another formula does not have a symmetric conflict", :no_api do
      stub_formula_loader formula("gcc") { url "gcc-1.0" }
      stub_formula_loader formula("glibc") { url "glibc-1.0" }

      foo = formula("foo") do
        url "https://brew.sh/foo-1.0.tgz"
      end
      stub_formula_loader foo

      bar = formula("bar") do
        url "https://brew.sh/bar-1.0.tgz"

        conflicts_with "foo"
      end

      fa = described_class.new bar
      fa.audit_conflicts

      expect(fa.problems.first[:message])
        .to match("Formula foo should also have a conflict declared with bar")
    end
  end

  describe "#audit_deprecate_disable" do
    specify "it warns when deprecate/disable reason is invalid" do
      fa = formula_auditor "foo", <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"

        deprecate! date: "2021-01-01", because: :foobar
        end
      RUBY

      mkdir_p fa.formula.prefix
      fa.audit_deprecate_disable
      expect(fa.problems.first[:message])
        .to match("foobar is not a valid deprecate! or disable! reason")
    end

    specify "it does not warn when deprecate/disable reason is valid" do
      fa = formula_auditor "foo", <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"

        deprecate! date: "2021-01-01", because: :repo_archived
        end
      RUBY

      mkdir_p fa.formula.prefix
      fa.audit_deprecate_disable
      expect(fa.problems).to be_empty
    end
  end

  describe "#audit_no_autobump" do
    it "warns when autobump exclusion reason is not suitable for new formula" do
      fa = formula_auditor "foo", <<~RUBY, new_formula: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"

          no_autobump! because: :requires_manual_review
        end
      RUBY

      fa.audit_no_autobump
      expect(fa.new_formula_problems.first[:message])
        .to match("`:requires_manual_review` is a temporary reason intended for existing packages, " \
                  "use a different reason instead.")
    end

    it "does not warn when autobump exclusion reason is allowed" do
      fa = formula_auditor "foo", <<~RUBY, new_formula: true
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"

          no_autobump! because: "foo bar"
        end
      RUBY

      fa.audit_no_autobump
      expect(fa.new_formula_problems).to be_empty
    end
  end
end
