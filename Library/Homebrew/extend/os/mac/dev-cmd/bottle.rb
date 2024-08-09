# typed: true # This cannot be `# typed: strict` due to the use of `undef`.
# frozen_string_literal: true

module Homebrew
  module DevCmd
    class Bottle < AbstractCommand
      undef tar_args

      sig { returns(T::Array[String]) }
      def tar_args
        if MacOS.version >= :catalina
          ["--no-mac-metadata", "--no-acls", "--no-xattrs"].freeze
        else
          [].freeze
        end
      end

      undef gnu_tar

      sig { params(gnu_tar_formula: Formula).returns(String) }
      def gnu_tar(gnu_tar_formula)
        "#{gnu_tar_formula.opt_bin}/gtar"
      end
    end
  end
end
