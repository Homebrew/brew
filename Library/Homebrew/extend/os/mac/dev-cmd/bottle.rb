# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module DevCmd
      module Bottle
        sig { returns(T::Array[String]) }
        def tar_args
          ["--no-mac-metadata", "--no-acls", "--no-xattrs"].freeze
        end

        sig { params(gnu_tar_formula: Formula).returns(String) }
        def gnu_tar(gnu_tar_formula)
          "#{gnu_tar_formula.opt_bin}/gtar"
        end
      end
    end
  end
end

Homebrew::DevCmd::Bottle.prepend(OS::Mac::DevCmd::Bottle)
