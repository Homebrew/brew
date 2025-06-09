cask "with-on-arch-conditional" do
  folder = on_arch_conditional arm: "arm-dir/", intel: "intel-dir/"

  url "https://brew.sh/#{folder}TestCask-#{version}.dmg"
  homepage "https://brew.sh/"

  app "TestCask.app"
end
