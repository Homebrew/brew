# typed: true
# frozen_string_literal: true

class Formula
  undef valid_platform?
  undef std_cmake_args

  sig { returns(T::Boolean) }
  def valid_platform?
    requirements.none?(LinuxRequirement)
  end

  sig {
    params(
      install_prefix: T.any(String, Pathname),
      install_libdir: T.any(String, Pathname),
      find_framework: String,
    ).returns(T::Array[String])
  }
  def std_cmake_args(install_prefix: prefix, install_libdir: "lib", find_framework: "LAST")
    args = generic_std_cmake_args(install_prefix:, install_libdir:,
                                  find_framework:)

    # Avoid false positives for clock_gettime support on 10.11.
    # CMake cache entries for other weak symbols may be added here as needed.
    args << "-DHAVE_CLOCK_GETTIME:INTERNAL=0" if MacOS.version == "10.11" && MacOS::Xcode.version >= "8.0"

    # Ensure CMake is using the same SDK we are using.
    args << "-DCMAKE_OSX_SYSROOT=#{MacOS.sdk_for_formula(self).path}" if MacOS.sdk_root_needed?

    args
  end
end
