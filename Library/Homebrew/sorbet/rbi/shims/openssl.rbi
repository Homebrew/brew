# typed: strict
# frozen_string_literal: true

class OpenSSL::X509::Certificate
  sig { params(data: String).returns(T::Array[OpenSSL::X509::Certificate]) }
  def self.load(data); end

  sig { returns(String) }
  def tbs_bytes; end
end
