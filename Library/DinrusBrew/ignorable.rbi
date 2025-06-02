# typed: strict

module Ignorable
  include Kernel
  # This is a workaround to enable `raise` to be aliased
  # @see https://github.com/sorbet/sorbet/issues/2378#issuecomment-569474238
  def self.raise(*); end
end
