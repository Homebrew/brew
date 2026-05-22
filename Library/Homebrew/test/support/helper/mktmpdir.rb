# typed: strict
# frozen_string_literal: true

module Test
  module Helper
    module MkTmpDir
      extend T::Sig

      sig do
        params(
          prefix_suffix: T.nilable(T.any(String, T::Array[String])),
          blk: T.nilable(T.proc.params(tmpdir: Pathname).returns(T.untyped)),
        ).returns(T.untyped)
      end
      def mktmpdir(prefix_suffix = nil, &blk)
        new_dir = Pathname.new(Dir.mktmpdir(prefix_suffix, HOMEBREW_TEMP))
        return blk.call(new_dir) if blk

        new_dir
      end
    end
  end
end
