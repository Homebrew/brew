require_relative "line_editor/basic"
require_relative "line_editor/readline"

class Bundler::Thor
  module LineEditor
    def self.readline(prompt, options = {})
      best_available.new(prompt, options).readline
    end

    def self.best_available
      [
        Bundler::Thor::LineEditor::Readline,
        Bundler::Thor::LineEditor::Basic
      ].detect(&:available?)
    end
  end
end
