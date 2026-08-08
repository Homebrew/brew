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
        subject = (type == :cask) ? "This cask" : "This formula"

        return "#{subject} requires macOS." unless version_specified?

        case comparator
        when ">="
          "#{subject} does not run on macOS versions older than #{T.cast(version, MacOSVersion).pretty_name}."
        when "<="
          case type
          when :formula
            <<~EOS
              #{subject} either does not compile or function as expected on macOS
              versions newer than #{T.cast(version, MacOSVersion).pretty_name} due to an upstream incompatibility.
            EOS
          when :cask
            "#{subject} does not run on macOS versions newer than #{T.cast(version, MacOSVersion).pretty_name}."
          else
            ""
          end
        else
          if version.respond_to?(:to_ary) || version.is_a?(Array)
            *versions, last = T.unsafe(version).map(&:pretty_name)
            return "#{subject} does not run on macOS versions other than #{versions.join(", ")} and #{last}."
          end

          "#{subject} does not run on macOS versions other than #{T.cast(version, MacOSVersion).pretty_name}."
        end
      end
    end
  end
end

MacOSRequirement.prepend(OS::Mac::MacOSRequirement)
