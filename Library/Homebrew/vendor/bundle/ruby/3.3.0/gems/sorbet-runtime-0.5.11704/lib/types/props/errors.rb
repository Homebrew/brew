# frozen_string_literal: true
# typed: strict

module T::Props
  class Error < StandardError; end
  class InvalidValueError < Error; end
  class ImmutableProp < Error; end
end
