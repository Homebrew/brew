# typed: true
# frozen_string_literal: true

class DevelopmentTools
  class << self
    sig { params(tool: T.any(String, Symbol)).returns(T.nilable(Pathname)) }
    def locate(tool)
      (@locate ||= {}).fetch(tool) do |key|
        @locate[key] = if needs_build_formulae? &&
                          (binutils_path = HOMEBREW_PREFIX/"opt/binutils/bin/#{tool}").executable?
          binutils_path
        elsif needs_build_formulae? && (glibc_path = HOMEBREW_PREFIX/"opt/glibc/bin/#{tool}").executable?
          glibc_path
        elsif (homebrew_path = HOMEBREW_PREFIX/"bin/#{tool}").executable?
          homebrew_path
        elsif File.executable?(system_path = "/usr/bin/#{tool}")
          Pathname.new system_path
        end
      end
    end

    sig { returns(Symbol) }
    def default_compiler
      :gcc
    end

    sig { returns(T::Boolean) }
    def needs_libc_formula?
      return @needs_libc_formula if defined? @needs_libc_formula

      @needs_libc_formula = OS::Linux::Glibc.below_ci_version?
    end

    sig { returns(T::Boolean) }
    def needs_compiler_formula?
      return @needs_compiler_formula if defined? @needs_compiler_formula

      gcc = "/usr/bin/gcc"
      @needs_compiler_formula = if File.exist?(gcc)
        gcc_version(gcc) < OS::LINUX_GCC_CI_VERSION
      else
        true
      end
    end

    sig { returns(T::Hash[String, T.nilable(String)]) }
    def build_system_info
      generic_build_system_info.merge({
        "glibc_version"     => OS::Linux::Glibc.version.to_s.presence,
        "oldest_cpu_family" => Hardware.oldest_cpu.to_s,
      })
    end
  end
end
