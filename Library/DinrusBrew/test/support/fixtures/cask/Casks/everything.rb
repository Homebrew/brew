# Used to test cask hash generation.
cask "everything" do
  version "1.2.3"

  language "en", default: true do
    sha256 "c64c05bdc0be845505d6e55e69e696a7f50d40846e76155f0c85d5ff5e7bbb84"
    "en-US"
  end
  language "eo" do
    sha256 "e8ffa07370a7fb7e1696b04c269e01d3459725965a32facdd54629a95d148908"
    "eo"
  end

  url "https://cachefly.everything.app/releases/Everything_#{version}.zip",
      user_agent: :fake,
      cookies:    { "ALL" => "1234" }
  name "Everything"
  desc "Little bit of everything"
  homepage "https://www.everything.app/"

  auto_updates true
  conflicts_with formula: "nothing"
  depends_on cask: "something"
  container type: :naked

  app "Everything.app"
  installer script: {
    executable:   "~/just/another/path/install.sh",
    args:         ["--mode=silent"],
    sudo:         true,
    print_stderr: false,
  }

  uninstall launchctl: "com.every.thing.agent",
            signal:    [
              ["TERM", "com.every.thing.controller#{version.major}"],
              ["TERM", "com.every.thing.bin"],
            ],
            kext:      "com.every.thing.driver",
            delete:    "/Library/EverythingHelperTools"

  zap trash: [
    "~/.everything",
    "~/Library/Everything",
  ]

  caveats "Installing everything might take a while..."
end
