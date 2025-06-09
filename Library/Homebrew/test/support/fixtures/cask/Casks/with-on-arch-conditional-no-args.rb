cask "with-on-arch-conditional-no-args" do
  folder = on_arch_conditional

  url "https://brew.sh/#{folder}TestCask-#{version}.dmg"
  homepage "https://brew.sh/"

  app "TestCask.app"
end
