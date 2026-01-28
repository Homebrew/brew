# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module FormulaCellarChecks
      sig { params(filename: ::Pathname).returns(T::Boolean) }
      def valid_library_extension?(filename)
        super || filename.basename.to_s.include?(".so.")
      end
    end
  end
end

FormulaCellarChecks.prepend(OS::Linux::FormulaCellarChecks)
