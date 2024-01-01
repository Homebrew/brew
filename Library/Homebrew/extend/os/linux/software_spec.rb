# typed: strict
# frozen_string_literal: true

class BottleSpecification
  sig { params(tag: Utils::Bottles::Tag).returns(T::Boolean) }
  def skip_relocation?(tag: Utils::Bottles.tag)
    false
  end
end
