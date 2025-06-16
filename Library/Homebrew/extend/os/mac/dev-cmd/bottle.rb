# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module DevCmd
      module Bottle
        sig { returns(T::Array[String]) }
        def tar_args
          if MacOS.version >= :catalina
            ["--no-mac-metadata", "--no-acls", "--no-xattrs"].freeze
          else
            [].freeze
          end
        end

        sig { params(gnu_tar_formula: Formula).returns(String) }
        def gnu_tar(gnu_tar_formula)
          "#{gnu_tar_formula.opt_bin}/gtar"
        end

        sig { params(formula: Formula).returns(T::Array[Regexp]) }
        def formula_ignores(formula)
          ignores = super

          cellar_regex = Regexp.escape(HOMEBREW_CELLAR)
          prefix_regex = Regexp.escape(HOMEBREW_PREFIX)

          ignores << case formula.name
          # On Linux, GCC installation can be moved so long as the whole directory tree is moved together:
          # https://gcc-help.gcc.gnu.narkive.com/GnwuCA7l/moving-gcc-from-the-installation-path-is-it-allowed.
          when Version.formula_optionally_versioned_regex(:gcc)
            Regexp.union(%r{#{cellar_regex}/gcc}, %r{#{prefix_regex}/opt/gcc}) if OS.linux?
          # binutils is relocatable for the same reason: https://github.com/Homebrew/brew/pull/11899#issuecomment-906804451.
          when Version.formula_optionally_versioned_regex(:binutils)
            %r{#{cellar_regex}/binutils} if OS.linux?
          end

          ignores.compact
        end
      end
    end
  end
end

Homebrew::DevCmd::Bottle.prepend(OS::Mac::DevCmd::Bottle)
