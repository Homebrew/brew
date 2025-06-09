cask "with-on-system-conditional" do
  folder = on_system_conditional linux: "linux-dir/", macos: "macos-dir/"

  url "https://brew.sh/#{folder}TestCask-#{version}.dmg"
  homepage "https://brew.sh/"

  app "TestCask.app"
end
