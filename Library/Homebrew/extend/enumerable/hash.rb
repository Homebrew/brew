# typed: strict
# frozen_string_literal: true

class Hash
  # {Hash#reject} has its own definition, so this needs one too.
  def compact_blank
    reject do |_k, v|
      case v
      when Object then v.blank?
      end
    end
  end
end
