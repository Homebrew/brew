# typed: true
# frozen_string_literal: true

require "fileutils"
require "system_command"

RSpec.describe "shims/shared/git", type: :system do
  let(:tool) { "homebrew-shim-test" }

  it "does not exec itself from outside shims/shared" do
    shims_dir = mktmpdir/"Library/Homebrew/shims/super"
    shims_dir.mkpath
    FileUtils.cp HOMEBREW_SHIMS_PATH/"shared/git", shims_dir/tool
    ENV["PATH"] = PATH.new(ENV.fetch("PATH")).prepend(shims_dir).to_s

    expect(SystemCommand.run(shims_dir/tool, timeout: 10).stderr).to eq("You must: brew install #{tool}\n")
  end

  it "does not exec the same shim from another Homebrew checkout" do
    shims_dirs = %w[a b].map do |checkout|
      shims_dir = mktmpdir/checkout/"Library/Homebrew/shims/shared"
      shims_dir.mkpath
      FileUtils.cp HOMEBREW_SHIMS_PATH/"shared/git", shims_dir
      FileUtils.ln_s "git", shims_dir/tool
      shims_dir
    end
    ENV["PATH"] = PATH.new(ENV.fetch("PATH")).prepend(*shims_dirs).to_s

    expect(SystemCommand.run(shims_dirs.fetch(0)/tool, timeout: 10).stderr)
      .to eq("You must: brew install #{tool}\n")
  end

  context "when selecting Apple Git" do
    let(:test_root) { mktmpdir }
    let(:developer_dir) { test_root/"Developer Tools" }
    let(:selected_path) { developer_dir.to_s }
    let(:shim) { test_root/"git" }

    before do
      developer_dir.mkpath
      (test_root/"xcode-select").write <<~SH
        #!/bin/bash
        echo "#{selected_path}"
      SH
      (test_root/"xcode-select").chmod(0755)
      (test_root/"usr/bin").mkpath
      (test_root/"usr/bin/git").write "#!/bin/bash\necho popup-stub\n"
      (test_root/"usr/bin/git").chmod(0755)
      (test_root/"xcrun").write "#!/bin/bash\necho '#{test_root}/usr/bin/git'\n"
      (test_root/"xcrun").chmod(0755)
      shim.write (HOMEBREW_SHIMS_PATH/"shared/git").read
        .gsub("/usr/bin/xcode-select", "#{test_root}/xcode-select")
        .gsub("/usr/bin/xcrun", "#{test_root}/xcrun")
        .gsub("/Applications/Xcode.app", "#{test_root}/Xcode.app")
        .sub('path="/usr/bin/${SHIM_FILE}"', "path=\"#{test_root}/usr/bin/${SHIM_FILE}\"")
      shim.chmod(0755)
      # Exclude Linux's /bin/git so it cannot take precedence over the Apple Git fixture.
      ENV["PATH"] = "/usr/bin"
      ENV["HOMEBREW_PREFIX"] = (test_root/"prefix").to_s
      ENV.delete("HOMEBREW_GIT")
    end

    it "does not invoke the system stub when the selected directory has no Git" do
      expect(SystemCommand.run(shim).stderr).to eq("You must: brew install git\n")
    end

    it "uses Git from the selected developer tools when installed" do
      (developer_dir/"usr/bin").mkpath
      (developer_dir/"usr/bin/git").write "#!/bin/bash\necho installed-git\n"
      (developer_dir/"usr/bin/git").chmod(0755)

      expect(SystemCommand.run(shim).stdout).to eq("installed-git\n")
    end

    context "when xcode-select points to the root directory" do
      let(:selected_path) { "/" }

      it "does not invoke the system stub" do
        expect(SystemCommand.run(shim).stderr).to eq("You must: brew install git\n")
      end
    end
  end
end
