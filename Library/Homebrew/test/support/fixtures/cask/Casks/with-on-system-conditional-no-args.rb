cask "with-on-system-conditional-no-args" do
  folder = on_system_conditional

  url "https://brew.sh/#{folder}TestCask-#{version}.dmg"
  homepage "https://brew.sh/"

  app "TestCask.app"
end
