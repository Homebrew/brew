# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"
require "cask/caskroom"

module Cask
  module Artifact
    # Artifact corresponding to the `app` stanza.
    class App < Moved
      sig {
        override.params(
          adopt:        T::Boolean,
          auto_updates: T.nilable(T::Boolean),
          force:        T::Boolean,
          verbose:      T::Boolean,
          predecessor:  T.nilable(Cask),
          successor:    T.nilable(Cask),
          reinstall:    T::Boolean,
          command:      T.class_of(SystemCommand),
        ).void
      }
      def install_phase(
        adopt: false,
        auto_updates: false,
        force: false,
        verbose: false,
        predecessor: nil,
        successor: nil,
        reinstall: false,
        command: SystemCommand
      )
        # Prepare leading script permissions before App Management protects the installed app.
        # Keeping this in the normal sandbox avoids giving postflight code inherited TCC access.
        if !adopt && target.extname == ".app" && target.dirname == cask.config.appdir &&
           source.directory? && !source.symlink? && source.realpath.ascend.include?(cask.staged_path.realpath)
          cask.artifacts.grep(PostflightSteps).flat_map(&:steps).each do |step|
            permissions = step["permissions"]
            break if step["type"] != "set_permissions" || step["non_recursive"] != true || step["guards"].present?
            # 0755 survives the app permission normalisation below without granting group/world writes.
            break if !permissions.is_a?(String) || !permissions.match?(/\A0?[0-7]{3}\z/) || permissions.oct != 0755

            paths = step["paths"]
            break unless paths.is_a?(Array)

            first_spec = paths.first
            break unless first_spec.is_a?(Hash)

            step_app = cask.artifacts.grep(App).find do |app|
              app.target.dirname == cask.config.appdir && app.target.extname == ".app" &&
                app.target.basename.to_s == first_spec.fetch("path").split("/", 2).first
            end
            break unless step_app

            staged_paths = paths.filter_map do |spec|
              next if !spec.is_a?(Hash) || spec["base"] != "appdir"
              next if spec.fetch("path").match?(/[*?\[\]{}]/)

              components = spec.fetch("path").split("/", -1)
              next if components.length < 2 || components.first != step_app.target.basename.to_s ||
                      components.intersect?(::Utils::INVALID_PATH_COMPONENTS)

              path = step_app.source.join(*components.drop(1))
              next if !path.file? || path.symlink? || path.stat.nlink != 1 ||
                      path.realpath.ascend.exclude?(step_app.source.realpath)

              { "base" => "staged_path", "path" => path.relative_path_from(cask.staged_path).to_s }
            end
            break if staged_paths.length != paths.length
            # Use identity because app artefacts compare equal for installation order.
            next unless step_app.equal?(self)

            break unless Sandbox.use_for?("preparing cask app permissions", warn_without_sandbox: false)

            PreflightSteps.new(cask, [step.slice("type", "permissions", "non_recursive")
                                         .merge("paths" => staged_paths)]).install_phase(command:)
          end
        end

        super

        odebug "Fixing up '#{target}' permissions for installation to '#{target.parent}'"
        system_dir = target.ascend
                           .take_while { it.to_s != Dir.home && (it.to_s != "/" || it == target.parent) }
                           .any? { OS::Mac.system_dir?(it) }
        permissions = "go-w"
        # Ensure that globally installed applications can be accessed by all users.
        permissions = "a+rX,#{permissions}" if system_dir

        # We shell out to `chmod` instead of using `FileUtils.chmod` so that using `+X` works correctly.
        command.run!("chmod", args: ["-R", permissions, target], sudo: nil)

        sudo = false unless system_dir
        command.run("chgrp", args: ["-hR", Caskroom.expected_caskroom_group, target],
                             sudo:, must_succeed: system_dir, print_stderr: system_dir)
      end
    end
  end
end
