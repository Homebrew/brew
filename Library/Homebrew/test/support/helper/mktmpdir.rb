# typed: true
# frozen_string_literal: true

module Test
  module Helper
    module MkTmpDir
      def mktmpdir(prefix_suffix = nil, &block)
        new_dir = Pathname.new(Dir.mktmpdir(prefix_suffix, HOMEBREW_TEMP))
        return yield(new_dir) if block

        new_dir
      end
    end
  end
end
