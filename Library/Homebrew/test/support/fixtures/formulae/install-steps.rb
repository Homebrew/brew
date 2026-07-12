# typed: false
# frozen_string_literal: true

class InstallSteps < Formula
  Cache = type_template { { fixed: T::Hash[Symbol, T.untyped] } }

  desc "Formula with structured install steps"
  homepage "https://brew.sh/install-steps"
  url "https://brew.sh/install-steps-1.0"

  post_install_steps do
    mkdir_p "log/install-steps"
    touch "install-steps/state"
    mv "move-source", "move-target"
    move_children "move-children-source", "move-children-target"
    ln_sf "move-target", "linked-target", source_base: :relative, uninstall: true
    init_data_dir "lib/install-steps", using: :postgresql_initdb
  end
end
