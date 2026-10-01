# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Formula
      extend T::Helpers

      requires_ancestor { ::Formula }

      JAVA_HEADLESS_OPTION = "-Djava.awt.headless=true"
      private_constant :JAVA_HEADLESS_OPTION

      sig { returns(T::Boolean) }
      def valid_platform?
        supports_macos?
      end

      sig {
        params(
          install_prefix: T.any(String, ::Pathname),
          install_libdir: T.any(String, ::Pathname),
          find_framework: String,
        ).returns(T::Array[String])
      }
      def std_cmake_args(install_prefix: prefix, install_libdir: "lib", find_framework: "LAST")
        args = super

        # Ensure CMake is using the same SDK we are using.
        sdk = MacOS.sdk_for_formula(self)
        raise "No macOS SDK found. Install Xcode or the Command Line Tools." if sdk.nil?

        args << "-DCMAKE_OSX_SYSROOT=#{sdk.path}"

        args
      end

      sig { returns(T::Array[String]) }
      def std_swift_args
        ["--disable-sandbox"].concat(super)
      end

      sig {
        params(
          prefix:       T.any(String, ::Pathname),
          release_mode: Symbol,
          cpu:          T.nilable(Symbol),
        ).returns(T::Array[String])
      }
      def std_zig_args(prefix: self.prefix, release_mode: :fast, cpu: nil)
        args = super
        args << "-fno-rosetta" if ::Hardware::CPU.arm?
        args
      end

      # The sandbox denies `mach-lookup`, so AWT cannot reach the WindowServer and aborts
      # the JVM. Headless AWT never connects to it and still renders images off-screen.
      sig { params(home: ::Pathname).returns(T::Hash[Symbol, String]) }
      def common_sandbox_env(home)
        env = super
        env.merge(_JAVA_OPTIONS: [env[:_JAVA_OPTIONS], JAVA_HEADLESS_OPTION].compact.join(" "))
      end

      # The `java` launcher decides from the options it parses itself, its arguments and
      # `JDK_JAVA_OPTIONS`, whether to show a jar's `SplashScreen-Image`, which aborts under
      # the sandbox like the rest of AWT. OpenJDK's `configure` rejects a boot JDK that reports
      # picked-up options, so the build phase must not see this variable.
      sig { params(testpath: ::Pathname).returns(T::Hash[Symbol, String]) }
      def test_sandbox_env(testpath)
        super.merge(JDK_JAVA_OPTIONS: JAVA_HEADLESS_OPTION)
      end
    end
  end
end

Formula.prepend(OS::Mac::Formula)
