# typed: strict
# frozen_string_literal: true

module Utils
  module Path
    sig { params(parent: T.any(Pathname, String), child: T.any(Pathname, String)).returns(T::Boolean) }
    def self.child_of?(parent, child)
      parent_pathname = Pathname(parent).expand_path
      child_pathname = Pathname(child).expand_path
      child_pathname.ascend { |p| return true if p == parent_pathname }
      false
    end
  end
end
