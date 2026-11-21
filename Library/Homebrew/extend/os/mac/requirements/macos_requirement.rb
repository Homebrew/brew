# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module MacOSRequirement
      extend T::Helpers

      requires_ancestor { ::MacOSRequirement }

      sig { returns(T::Boolean) }
      def macos_version_satisfied?
        !version_specified? || Array(version).any? { |v| OS::Mac.version.compare(comparator, v) }
      end

      sig { params(type: Symbol).returns(String) }
      def message(type: :formula)
        for_cask = type == :cask
        subject = for_cask ? "This cask" : "This formula"

        return "#{subject} requires macOS." unless version_specified?

        case comparator
        when ">="
          pretty_version = T.cast(version, MacOSVersion).pretty_name
          "#{subject} does not run on macOS versions older than #{pretty_version}."
        when "<="
          case type
          when :formula
            pretty_version = T.cast(version, MacOSVersion).pretty_name
            <<~EOS
              #{subject} either does not compile or function as expected on macOS
              versions newer than #{pretty_version} due to an upstream incompatibility.
            EOS
          when :cask
            pretty_version = T.cast(version, MacOSVersion).pretty_name
            "#{subject} does not run on macOS versions newer than #{pretty_version}."
          else
            ""
          end
        else
          all_versions = version
          if all_versions.is_a?(Array)
            *versions, last = all_versions.map(&:pretty_name)
            return "#{subject} does not run on macOS versions other than #{versions.join(", ")} and #{last}."
          end

          pretty_version = T.cast(version, MacOSVersion).pretty_name
          "#{subject} does not run on macOS versions other than #{pretty_version}."
        end
      end
    end
  end
end

MacOSRequirement.prepend(OS::Mac::MacOSRequirement)
