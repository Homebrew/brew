# frozen_string_literal: true

module Test
  module Helper
    module MkTmpDir
      def mktmpdir(prefix_suffix = nil)
        new_dir = Pathname.new(Dir.mktmpdir(prefix_suffix, HOMEBREW_TEMP))
        return yield new_dir if block_given?

        new_dir
      end
    end
  end
end
