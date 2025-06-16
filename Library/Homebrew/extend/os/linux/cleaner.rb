# typed: strict
# frozen_string_literal: true

class Cleaner
  private

  sig { params(path: Pathname).returns(T::Boolean) }
  def executable_path?(path)
    path.elf? || path.text_executable?
  end
end
