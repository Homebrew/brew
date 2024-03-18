# frozen_string_literal: true

require "dev-cmd/audit"
require "formulary"
require "cmd/shared_examples/args_parse"
require "utils/spdx"

RSpec.describe "brew audit" do
  it_behaves_like "parseable arguments"
end

module Count
  def self.increment
    @count ||= 0
    @count += 1
  end
end

module Homebrew
  RSpec.describe FormulaTextAuditor do
    alias_matcher :have_data, :be_data
    alias_matcher :have_end, :be_end
    alias_matcher :have_trailing_newline, :be_trailing_newline

    let(:dir) { mktmpdir }

    def formula_text(name, body = nil, options = {})
      path = dir/"#{name}.rb"

      path.write <<~RUBY
        class #{Formulary.class_s(name)} < Formula
          #{body}
        end
        #{options[:patch]}
      RUBY

      described_class.new(path)
    end

    specify "simple valid Formula" do
      ft = formula_text "valid", <<~RUBY
        url "https://www.brew.sh/valid-1.0.tar.gz"
      RUBY

      expect(ft).to have_trailing_newline

      expect(ft =~ /\burl\b/).to be_truthy
      expect(ft.line_number(/desc/)).to be_nil
      expect(ft.line_number(/\burl\b/)).to eq(2)
      expect(ft).to include("Valid")
    end

    specify "#trailing_newline?" do
      ft = formula_text "newline"
      expect(ft).to have_trailing_newline
    end
  end

  RSpec.describe FormulaAuditor do
    let(:dir) { mktmpdir }
    let(:foo_version) { Count.increment }
    let(:formula_subpath) { "Formula/foo#{foo_version}.rb" }
    let(:origin_tap_path) { Tap::TAP_DIRECTORY/"homebrew/homebrew-foo" }
    let(:origin_formula_path) { origin_tap_path/formula_subpath }
    let(:tap_path) { Tap::TAP_DIRECTORY/"homebrew/homebrew-bar" }
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
         "as what is indicated on its Github repo", :needs_network do
        formula_text = <<~RUBY
          class Cask < Formula
            url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
            head "https://github.com/cask/cask.git"
            license "GPL-3.0"
          end
        RUBY
        fa = formula_auditor "cask", formula_text, spdx_license_data:,
                             online: true, core_tap: true, new_formula: true

        fa.audit_license
        expect(fa.problems).to be_empty
      end

      it "checks online and verifies that a standard license id with AND is the same " \
         "as what is indicated on its Github repo", :needs_network do
        formula_text = <<~RUBY
          class Cask < Formula
            url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
            head "https://github.com/cask/cask.git"
            license all_of: ["GPL-3.0-or-later", "MIT"]
          end
        RUBY
        fa = formula_auditor "cask", formula_text, spdx_license_data:,
                             online: true, core_tap: true, new_formula: true

        fa.audit_license
        expect(fa.problems).to be_empty
      end

      it "checks online and verifies that a standard license id with WITH is the same " \
         "as what is indicated on its Github repo", :needs_network do
        formula_text = <<~RUBY
          class Cask < Formula
            url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
            head "https://github.com/cask/cask.git"
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
            head "https://github.com/cask/cask.git"
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
            head "https://github.com/cask/cask.git"
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
            head "https://github.com/cask/cask.git"
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
            head "https://github.com/cask/cask.git"
            license any_of: ["GPL-3.0-or-later", "MIT"]
          end
        RUBY

        fa.audit_license
        expect(fa.problems).to be_empty
      end

      it "checks online and detects that a formula-specified license is not " \
         "the same as what is indicated on its Github repository", :needs_network do
        formula_text = <<~RUBY
          class Cask < Formula
            url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
            head "https://github.com/cask/cask.git"
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
            head "https://github.com/cask/cask.git"
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
         "what is indicated on its Github repository", :needs_network do
        formula_text = <<~RUBY
          class Cask < Formula
            url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
            head "https://github.com/cask/cask.git"
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
         "what is indicated on its Github repository", :needs_network do
        formula_text = <<~RUBY
          class Cask < Formula
            url "https://github.com/cask/cask/archive/v0.8.4.tar.gz"
            head "https://github.com/cask/cask.git"
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

    describe "#audit_formula_name" do
      specify "no issue" do
        fa = formula_auditor "foo", <<~RUBY, core_tap: true, strict: true
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tgz"
            homepage "https://brew.sh"
          end
        RUBY

        fa.audit_formula_name
        expect(fa.problems).to be_empty
      end

      specify "uppercase formula name" do
        fa = formula_auditor "Foo", <<~RUBY
          class Foo < Formula
            url "https://brew.sh/Foo-1.0.tgz"
            homepage "https://brew.sh"
          end
        RUBY

        fa.audit_formula_name
        expect(fa.problems.first[:message]).to match "must not contain uppercase letters"
      end
    end

    describe "#audit_resource_name_matches_pypi_package_name_in_url" do
      it "reports a problem if the resource name does not match the python package name" do
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
          .to match("resource name should be `FooSomething` to match the PyPI package name")
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
      let(:throttle_list) { { throttled_formulae: { "foo" => 10 } } }
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

      it "allows versions with no throttle rate" do
        fa = formula_auditor "bar", <<~RUBY, core_tap: true, tap_audit_exceptions: throttle_list
          class Bar < Formula
            url "https://brew.sh/foo-1.0.1.tgz"
            sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          end
        RUBY

        fa.audit_specs
        expect(fa.problems).to be_empty
      end

      it "allows major/minor versions with throttle rate" do
        fa = formula_auditor "foo", <<~RUBY, core_tap: true, tap_audit_exceptions: throttle_list
          class Foo < Formula
            url "https://brew.sh/foo-1.0.0.tgz"
            sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          end
        RUBY

        fa.audit_specs
        expect(fa.problems).to be_empty
      end

      it "allows patch versions to be multiples of the throttle rate" do
        fa = formula_auditor "foo", <<~RUBY, core_tap: true, tap_audit_exceptions: throttle_list
          class Foo < Formula
            url "https://brew.sh/foo-1.0.10.tgz"
            sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          end
        RUBY

        fa.audit_specs
        expect(fa.problems).to be_empty
      end

      it "doesn't allow patch versions that aren't multiples of the throttle rate" do
        fa = formula_auditor "foo", <<~RUBY, core_tap: true, tap_audit_exceptions: throttle_list
          class Foo < Formula
            url "https://brew.sh/foo-1.0.1.tgz"
            sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
          end
        RUBY

        fa.audit_specs
        expect(fa.problems.first[:message]).to match "should only be updated every 10 releases on multiples of 10"
      end

      it "allows non-versioned formulae to have a `HEAD` spec" do
        fa = formula_auditor "bar", <<~RUBY, core_tap: true, tap_audit_exceptions: versioned_head_spec_list
          class Bar < Formula
            url "https://brew.sh/foo-1.0.tgz"
            sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
            head "https://brew.sh/foo.git"
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
            head "https://brew.sh/foo.git"
          end
        RUBY

        fa.audit_specs
        expect(fa.problems.first[:message]).to match "Versioned formulae should not have a `HEAD` spec"
      end

      it "allows versioned formulae on the allowlist to have a `HEAD` spec" do
        fa = formula_auditor "foo", <<~RUBY, core_tap: true, tap_audit_exceptions: versioned_head_spec_list
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tgz"
            sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"
            head "https://brew.sh/foo.git"
          end
        RUBY

        fa.audit_specs
        expect(fa.problems).to be_empty
      end
    end

    describe "#audit_deps" do
      describe "a dependency on a macOS-provided keg-only formula" do
        describe "which is allowlisted" do
          subject { fa }

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

          its(:problems) { are_expected.to be_empty }
        end

        describe "which is not allowlisted", :needs_macos do
          subject { fa }

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

          its(:new_formula_problems) do
            are_expected.to include(a_hash_including(message: a_string_matching(/is provided by macOS/)))
          end
        end
      end
    end

    describe "#audit_stable_version" do
      subject do
        fa = described_class.new(Formulary.factory(formula_path), git: true)
        fa.audit_stable_version
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

      describe "versions" do
        context "when uncommitted should not decrease" do
          before { formula_gsub "foo-1.0.tar.gz", "foo-0.9.tar.gz" }

          it { is_expected.to match("stable version should not decrease (from 1.0 to 0.9)") }
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

    describe "#audit_revision" do
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

          it { is_expected.to match("revision should not decrease (from 2 to 1)") }
        end

        describe "should not be removed with the same version" do
          before { formula_gsub_origin_commit "revision 2" }

          it { is_expected.to match("revision should not decrease (from 2 to 0)") }
        end

        describe "should not decrease with the same, uncommitted version" do
          before { formula_gsub "revision 2", "revision 1" }

          it { is_expected.to match("revision should not decrease (from 2 to 1)") }
        end

        describe "should be removed with a newer version" do
          before { formula_gsub_origin_commit "foo-1.0.tar.gz", "foo-1.1.tar.gz" }

          it { is_expected.to match("'revision 2' should be removed") }
        end

        describe "should be removed with a newer local version" do
          before { formula_gsub "foo-1.0.tar.gz", "foo-1.1.tar.gz" }

          it { is_expected.to match("'revision 2' should be removed") }
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

          it { is_expected.to match("revisions should only increment by 1") }
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

    describe "#audit_version_scheme" do
      subject do
        fa = described_class.new(Formulary.factory(formula_path), git: true)
        fa.audit_version_scheme
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

      describe "version_schemes" do
        describe "should not decrease with the same version" do
          before { formula_gsub_origin_commit "version_scheme 1" }

          it { is_expected.to match("version_scheme should not decrease (from 1 to 0)") }
        end

        describe "should not decrease with a new version" do
          before do
            formula_gsub_origin_commit "foo-1.0.tar.gz", "foo-1.1.tar.gz"
            formula_gsub_origin_commit "revision 2", ""
            formula_gsub_origin_commit "version_scheme 1", ""
          end

          it { is_expected.to match("version_scheme should not decrease (from 1 to 0)") }
        end

        describe "should only increment by 1" do
          before do
            formula_gsub_origin_commit "version_scheme 1", "# no version_scheme"
            formula_gsub_origin_commit "foo-1.0.tar.gz", "foo-1.1.tar.gz"
            formula_gsub_origin_commit "revision 2", ""
            formula_gsub_origin_commit "# no version_scheme", "version_scheme 3"
          end

          it { is_expected.to match("version_schemes should only increment by 1") }
        end
      end
    end

    describe "#audit_unconfirmed_checksum_change" do
      subject do
        fa = described_class.new(Formulary.factory(formula_path), git: true)
        fa.audit_unconfirmed_checksum_change
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

      describe "checksums" do
        describe "should not change with the same version" do
          before do
            formula_gsub(
              'sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"',
              'sha256 "3622d2a53236ed9ca62de0616a7e80fd477a9a3f862ba09d503da188f53ca523"',
            )
          end

          it { is_expected.to match("stable sha256 changed without the url/version also changing") }
        end

        describe "should not change with the same version when not the first commit" do
          before do
            formula_gsub_origin_commit(
              'sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"',
              'sha256 "3622d2a53236ed9ca62de0616a7e80fd477a9a3f862ba09d503da188f53ca523"',
            )
            formula_gsub_origin_commit "revision 2"
            formula_gsub_origin_commit "foo-1.0.tar.gz", "foo-1.1.tar.gz"
            formula_gsub(
              'sha256 "3622d2a53236ed9ca62de0616a7e80fd477a9a3f862ba09d503da188f53ca523"',
              'sha256 "e048c5e6144f5932d8672c2fade81d9073d5b3ca1517b84df006de3d25414fc1"',
            )
          end

          it { is_expected.to match("stable sha256 changed without the url/version also changing") }
        end

        describe "can change with the different version" do
          before do
            formula_gsub_origin_commit(
              'sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"',
              'sha256 "3622d2a53236ed9ca62de0616a7e80fd477a9a3f862ba09d503da188f53ca523"',
            )
            formula_gsub "foo-1.0.tar.gz", "foo-1.1.tar.gz"
            formula_gsub_origin_commit(
              'sha256 "3622d2a53236ed9ca62de0616a7e80fd477a9a3f862ba09d503da188f53ca523"',
              'sha256 "e048c5e6144f5932d8672c2fade81d9073d5b3ca1517b84df006de3d25414fc1"',
            )
          end

          it { is_expected.to be_nil }
        end

        describe "can be removed when switching schemes" do
          before do
            formula_gsub_origin_commit(
              'url "https://brew.sh/foo-1.0.tar.gz"',
              'url "https://foo.com/brew/bar.git", tag: "1.0", revision: "f5e00e485e7aa4c5baa20355b27e3b84a6912790"',
            )
            formula_gsub_origin_commit('sha256 "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"',
                                       "")
          end

          it { is_expected.to be_nil }
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
        # We don't really test FormulaTextAuditor here
        allow(File).to receive(:open).and_return("")
      end

      specify "it warns when conflicting with non-existing formula" do
        foo = formula("foo") do
          url "https://brew.sh/bar-1.0.tgz"

          conflicts_with "bar"
        end

        fa = described_class.new foo
        fa.audit_conflicts

        expect(fa.problems.first[:message])
          .to match("Can't find conflicting formula \"bar\"")
      end

      specify "it warns when conflicting with itself" do
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

      specify "it warns when another formula does not have a symmetric conflict" do
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
  end
end
