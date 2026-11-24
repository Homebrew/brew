# typed: true
# frozen_string_literal: true

require "system_command"

RSpec.describe "Executable selection", type: :system do
  def select_tool(tool, script: "")
    SystemCommand.run("/bin/bash", args: ["-c", <<~SH])
      source "#{HOMEBREW_LIBRARY_PATH}/utils.sh"
      select_tool #{tool} #{minimum} "#{brewed_tool}" "#{system_tool}" "#{custom_tool}" "${HOMEBREW_FORCE_BREWED_#{tool.upcase}}"
      #{script}
      printf '%s' "${HOMEBREW_SELECTED_TOOL}"
    SH
  end

  def write_tool(path, tool, version, status: 0)
    path.dirname.mkpath
    path.write <<~SH
      #!/bin/bash
      echo probe >> "#{test_root}/probes"
      echo '#{{ "git" => "git version", "curl" => "curl", "svn" => "svn, version" }.fetch(tool)} #{version} (vendor build)'
      exit #{status}
    SH
    path.chmod(0755)
  end

  def check_tool(tool, install: "return 1", script: "")
    tool_script = (HOMEBREW_LIBRARY_PATH/"utils/#{tool}.sh").read.gsub("/usr/bin/#{tool}", system_tool.to_s)
    SystemCommand.run("/bin/bash", args: ["-c", <<~SH])
      source "#{HOMEBREW_LIBRARY_PATH}/utils.sh"
      #{tool_script}
      brew() {
        echo "$*" >> "#{test_root}/installs"
        #{install}
      }
      setup_#{tool}
      check-#{tool}-version
      #{script}
      printf '%s' "${HOMEBREW_#{tool.upcase}}"
    SH
  end

  let(:tool) { RSpec.current_example.metadata.fetch(:tool) }
  let(:test_root) { mktmpdir }
  let(:system_tool) { test_root/"usr/bin"/tool }
  let(:brewed_tool) { test_root/"opt"/tool/"bin"/tool }
  let(:custom_tool) { test_root/"custom tools"/tool }
  let(:minimum) { { "git" => "2.30.0", "curl" => "7.41.0", "svn" => "1.1.0" }.fetch(tool) }

  before(:each, :tool) do
    write_tool(system_tool, tool, "8.0.0")
    write_tool(brewed_tool, tool, "9.0.0")
    write_tool(custom_tool, tool, "10.0.0")
    ENV["HOMEBREW_CACHE"] = (test_root/"cache").to_s
    ENV.delete("HOMEBREW_FORCE_BREWED_#{tool.upcase}")
  end

  test_each(%w[git curl svn]) do |tool|
    context "with #{tool}", tool: do
      it "prefers the newer installed Homebrew tool over the suggestion" do
        expect(select_tool(tool).stdout).to eq(brewed_tool.to_s)
      end

      it "prefers a newer system tool over Homebrew and the suggestion" do
        write_tool(system_tool, tool, "11.0.0")

        expect(select_tool(tool).stdout).to eq(system_tool.to_s)
      end

      it "honours FORCE with a working Homebrew tool even if the system is newer" do
        ENV["HOMEBREW_FORCE_BREWED_#{tool.upcase}"] = "1"
        write_tool(system_tool, tool, "11.0.0")

        expect(select_tool(tool).stdout).to eq(brewed_tool.to_s)
      end

      it "uses the system tool when Homebrew is missing" do
        brewed_tool.unlink

        expect(select_tool(tool).stdout).to eq(system_tool.to_s)
      end

      it "uses the system tool when Homebrew fails its version probe" do
        write_tool(brewed_tool, tool, "99.0.0", status: 1)

        expect(select_tool(tool).stdout).to eq(system_tool.to_s)
      end

      it "uses the system tool when Homebrew is too old" do
        write_tool(brewed_tool, tool, "1.0.0")

        expect(select_tool(tool).stdout).to eq(system_tool.to_s)
      end

      it "uses a suggestion with spaces only when both defaults are unsuitable" do
        write_tool(brewed_tool, tool, "1.0.0")
        system_tool.unlink

        expect(select_tool(tool).stdout).to eq(custom_tool.to_s)
      end

      it "rejects an outdated suggestion" do
        brewed_tool.unlink
        system_tool.unlink
        write_tool(custom_tool, tool, "1.0.0")

        expect(select_tool(tool).stdout).to be_empty
      end

      it "rejects a failed suggestion even if it prints a recent version" do
        brewed_tool.unlink
        system_tool.unlink
        write_tool(custom_tool, tool, "99.0.0", status: 1)

        expect(select_tool(tool).stdout).to be_empty
      end

      it "accepts the minimum version" do
        brewed_tool.unlink
        write_tool(system_tool, tool, minimum)

        expect(select_tool(tool).stdout).to eq(system_tool.to_s)
      end

      it "does not execute the suggested tool when a default works" do
        select_tool(tool)

        expect((test_root/"probes").read.lines.length).to eq(2)
      end

      it "reuses the cache across processes without version probes" do
        select_tool(tool)
        (test_root/"probes").unlink
        select_tool(tool)

        expect(test_root/"probes").not_to exist
      end

      it "rechecks replaced executables" do
        select_tool(tool)
        system_tool.unlink
        write_tool(system_tool, tool, "11.0.0")

        expect(select_tool(tool).stdout).to eq(system_tool.to_s)
      end

      it "rechecks a changed FORCE preference" do
        write_tool(system_tool, tool, "11.0.0")
        select_tool(tool)
        ENV["HOMEBREW_FORCE_BREWED_#{tool.upcase}"] = "1"

        expect(select_tool(tool).stdout).to eq(brewed_tool.to_s)
      end

      it "rechecks after explicit invalidation" do
        require "utils/tool"

        select_tool(tool)
        stub_const("HOMEBREW_CACHE", test_root/"cache")
        Utils::Tool.invalidate_cache(tool.to_sym)
        (test_root/"probes").unlink
        select_tool(tool)

        expect((test_root/"probes").read.lines.length).to eq(2)
      end

      it "works when the cache cannot be created" do
        (test_root/"cache").write "not a directory"

        expect(select_tool(tool).stdout).to eq(brewed_tool.to_s)
      end

      it "rechecks executables edited in place without changing their size" do
        select_tool(tool)
        write_tool(system_tool, tool, "9.1.0")

        expect(select_tool(tool).stdout).to eq(system_tool.to_s)
      end

      it "ignores an unreadable cache without printing an error" do
        select_tool(tool)
        (test_root/"cache/tool-selection"/tool).chmod(0000)

        expect(select_tool(tool).stderr).to be_empty
      end
    end
  end

  context "when checking the required version" do
    before do
      ENV["HOMEBREW_PREFIX"] = test_root.to_s
      ENV["HOMEBREW_#{tool.upcase}_PATH"] = custom_tool.to_s
      ENV.delete("HOMEBREW_MACOS")
      ENV.delete("HOMEBREW_NO_INSTALL_FROM_API")
      ENV.delete("HOMEBREW_INSTALLING_TOOL")
      (test_root/"installs").write ""
      [brewed_tool, system_tool, custom_tool].each { |path| write_tool(path, tool, "1.0.0") }
    end

    test_each(%w[git curl]) do |tool|
      context "with #{tool}", tool: do
        it "installs a suitable tool before reporting an error" do
          version_prefix = if tool == "git"
            "git version"
          else
            "curl"
          end
          result = check_tool(tool, install: <<~SH)
            [[ "${HOMEBREW_INSTALLING_TOOL}" == 1 && "${HOMEBREW_NO_AUTO_UPDATE}" == 1 ]] || return 1
            printf '#!/bin/bash\necho "#{version_prefix} 10.0.0"\n' > "#{brewed_tool}"
          SH

          expect([result.stdout, result.stderr, (test_root/"installs").read])
            .to eq([brewed_tool.to_s, "", "install #{tool}\n"])
        end

        it "reports the minimum, versions and paths only after installation fails" do
          result = check_tool(tool)
          label = if tool == "git"
            "Git"
          else
            "curl"
          end

          expect([result.status.exitstatus, result.stderr, (test_root/"installs").read]).to eq([
            1,
            "Error: Unable to automatically install a working #{label}.\n" \
            "Minimum required version: #{minimum}\n" +
            [brewed_tool, system_tool, custom_tool].map { |path|
              "#{"Your #{label} version".rjust(24)}: 1.0.0\n" \
                "#{"Your #{label} executable".rjust(24)}: #{path}\n"
            }.join,
            "install #{tool}\n",
          ])
        end

        it "reports an unavailable version for a broken executable" do
          write_tool(system_tool, tool, "99.0.0", status: 1)

          expect(check_tool(tool).stderr).to include("version: unavailable\n",
                                                     "executable: #{system_tool}\n")
        end

        it "rechecks the executable even when installation reports success" do
          expect(check_tool(tool, install: "return 0").status.exitstatus).to eq(1)
        end

        it "discards the cached probe after attempting installation" do
          version_prefix = if tool == "git"
            "git version"
          else
            "curl"
          end
          brewed_tool.write <<~SH
            #!/bin/bash
            [[ -f "#{test_root}/broken" ]] && exit 1
            echo '#{version_prefix} 10.0.0'
          SH
          system_tool.unlink
          custom_tool.unlink
          result = select_tool(tool, script: <<~SH)
            brew() { touch "#{test_root}/broken"; }
            setup_#{tool}() {
              select_tool #{tool} #{minimum} "#{brewed_tool}" "#{system_tool}" "#{custom_tool}" ""
            }
            install_tool #{tool} #{minimum}
          SH

          expect(result.status.exitstatus).to eq(1)
        end

        it "does not recursively install tools in the bootstrap subprocess" do
          ENV["HOMEBREW_INSTALLING_TOOL"] = "1"
          result = check_tool(tool)

          expect([result.stderr, (test_root/"installs").read]).to eq(["", ""])
        end

        it "does not install anything when a suitable system tool is available" do
          write_tool(system_tool, tool, "10.0.0")
          result = check_tool(tool)

          expect([result.stdout, result.stderr, (test_root/"installs").read]).to eq([system_tool.to_s, "", ""])
        end
      end
    end

    it "reports Git's error for a malformed configuration", tool: "git" do
      system_tool.write <<~SH
        #!/bin/bash
        echo 'fatal: bad config line 1 in file /example/.gitconfig' >&2
        exit 128
      SH

      expect(check_tool(tool).stderr).to include("fatal: bad config line 1 in file /example/.gitconfig")
    end

    context "with system curl", tool: "curl" do
      it "records system curl suitability across cache hits with and without FORCE" do
        write_tool(brewed_tool, tool, "9.0.0")
        results = ["7.40.0", "7.41.0"].product([nil, "1"]).map do |version, force|
          write_tool(system_tool, tool, version)
          ENV["HOMEBREW_FORCE_BREWED_CURL"] = force
          ENV.delete("HOMEBREW_SYSTEM_CURL_TOO_OLD")
          Array.new(2) do
            check_tool(tool, script: 'printf "%s " "${HOMEBREW_SYSTEM_CURL_TOO_OLD-unset}"').stdout
          end
        end

        expect([results, (test_root/"probes").read.lines.length, (test_root/"installs").read])
          .to eq([%w[1 1 unset unset].map { |flag| ["#{flag} #{brewed_tool}"] * 2 }, 8, ""])
      end

      it "clears the old-system flag after upgrading system curl" do
        write_tool(brewed_tool, tool, "9.0.0")
        check_tool(tool)
        ENV["HOMEBREW_SYSTEM_CURL_TOO_OLD"] = "1"
        write_tool(system_tool, tool, minimum)

        expect(check_tool(tool, script: 'printf "%s " "${HOMEBREW_SYSTEM_CURL_TOO_OLD-unset}"').stdout)
          .to eq("unset #{brewed_tool}")
      end
    end
  end

  it "exports a known curl version and removes an inherited version when unavailable" do
    result = SystemCommand.run("/bin/bash", args: ["-c", <<~SH])
      source "#{HOMEBREW_LIBRARY_PATH}/utils/curl.sh"
      select_tool() { HOMEBREW_SELECTED_TOOL=/usr/bin/curl; HOMEBREW_SELECTED_TOOL_VERSION="$version"; }
      for version in 8.7.1 ''
      do
        setup_curl
        /bin/bash -c 'echo "${HOMEBREW_CURL_VERSION-unset} ${HOMEBREW_CURL_VERSION_PATH-unset}"'
      done
    SH

    expect(result.stdout).to eq("8.7.1 /usr/bin/curl\nunset unset\n")
  end
end
