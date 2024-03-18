# typed: true
# frozen_string_literal: true

class Cleaner
  private

  undef executable_path?

  sig { params(path: Pathname).returns(T::Boolean) }
  def executable_path?(path)
    path.mach_o_executable? || path.text_executable?
  end
end
