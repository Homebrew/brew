# typed: strict

module RuboCop::Cop::Cask::CaskHelp
  # Sorbet doesn't understand `prepend`: https://github.com/sorbet/sorbet/issues/259
  include RuboCop::Cop::CommentsHelp
  requires_ancestor { RuboCop::Cop::Base }
end
