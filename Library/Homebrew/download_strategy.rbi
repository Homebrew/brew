# typed: strict

# This is a third-party implementation.
# rubocop:disable Lint/StructNewOverride
class Mechanize::HTTP
  ContentDisposition = Struct.new :type, :filename, :creation_date,
                                  :modification_date, :read_date, :size, :parameters
end
# rubocop:enable Lint/StructNewOverride

# This is a third-party implementation.
# rubocop:disable Style/OptionalBooleanParameter
class Mechanize::HTTP::ContentDispositionParser
  sig {
    params(content_disposition: String, header: T::Boolean)
      .returns(T.nilable(Mechanize::HTTP::ContentDisposition))
  }
  def parse(content_disposition, header = false); end
end
# rubocop:enable Style/OptionalBooleanParameter
