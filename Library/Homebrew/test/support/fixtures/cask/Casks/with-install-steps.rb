# typed: false
# frozen_string_literal: true

cask "with-install-steps" do
  version "1.2.3"
  sha256 "67cdb184572d137c3fbd7adc93b707117f0bfb0096684a43f82aa75f924d2c63"

  url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"
  name "With Install Steps"
  desc "Cask with structured install steps"
  homepage "https://brew.sh/with-install-steps"

  app "container"

  preflight_steps do
    mkdir_p "Prepared"
    set_permissions "Prepared", "0755"
    touch "Prepared/touched"
  end

  postflight_steps do
    mv "move-source", "Prepared/moved"
    ln_s "Prepared/moved", "PreparedLink", source_base: :relative, uninstall: true
  end

  uninstall_preflight_steps do
    mkdir "UninstallPrepared"
    set_ownership "UninstallPrepared", user: "root", group: "wheel"
    touch "UninstallPrepared/touched"
  end

  uninstall_postflight_steps do
    move_children "UninstallPrepared", "UninstallMoved"
  end
end
