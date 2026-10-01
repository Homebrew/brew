# typed: strict
# frozen_string_literal: true

module Test
  module Helper
    module MkTmpDir
      sig {
        type_parameters(:U).params(
          prefix_suffix: T.nilable(T.any(String, T::Array[String])),
          block:         T.nilable(T.proc.params(path: Pathname).returns(T.type_parameter(:U))),
        ).returns(T.any(Pathname, T.type_parameter(:U)))
      }
      def mktmpdir(prefix_suffix = nil, &block)
        new_dir = Pathname.new(Dir.mktmpdir(prefix_suffix, HOMEBREW_TEMP))
        return yield(new_dir) if block

        new_dir
      end
    end
  end
end
