# typed: true
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop makes sure that a formula's file permissions are correct.
      class Files < FormulaCop
        def audit_formula(node, _class_node, _parent_class_node, _body_node)
          return unless file_path

          # Codespaces routinely screws up all permissions so don't complain there.
          return if ENV["CODESPACES"] || ENV["HOMEBREW_CODESPACES"]

          offending_node(node)
          actual_mode = File.stat(file_path).mode
          # Check that the file is world-readable.
          if actual_mode & 0444 != 0444
            problem format("Incorrect file permissions (%03<actual>o): chmod %<wanted>s %<path>s",
                           actual: actual_mode & 0777,
                           wanted: "a+r",
                           path:   file_path)
          end
          # Check that the file is user-writeable.
          if actual_mode & 0200 != 0200
            problem format("Incorrect file permissions (%03<actual>o): chmod %<wanted>s %<path>s",
                           actual: actual_mode & 0777,
                           wanted: "u+w",
                           path:   file_path)
          end
          # Check that the file is *not* other-writeable.
          return if actual_mode & 0002 != 002

          problem format("Incorrect file permissions (%03<actual>o): chmod %<wanted>s %<path>s",
                         actual: actual_mode & 0777,
                         wanted: "o-w",
                         path:   file_path)
        end
      end
    end
  end
end
