# frozen_string_literal: true
##
# Basic OpenSSL-based package signing class.

require_relative "../user_interaction"

class Gem::Security::Signer
  include Gem::UserInteraction

  ##
  # The chain of certificates for signing including the signing certificate

  attr_accessor :cert_chain

  ##
  # The private key for the signing certificate

  attr_accessor :key

  ##
  # The digest algorithm used to create the signature

  attr_reader :digest_algorithm

  ##
  # The name of the digest algorithm, used to pull digests out of the hash by
  # name.

  attr_reader :digest_name # :nodoc:

  ##
  # Gem::Security::Signer options

  attr_reader :options

  DEFAULT_OPTIONS = {
    expiration_length_days: 365,
  }.freeze

  ##
  # Attempts to re-sign an expired cert with a given private key
  def self.re_sign_cert(expired_cert, expired_cert_path, private_key)
    return unless expired_cert.not_after < Time.now

    expiry = expired_cert.not_after.strftime("%Y%m%d%H%M%S")
    expired_cert_file = "#{File.basename(expired_cert_path)}.expired.#{expiry}"
    new_expired_cert_path = File.join(Gem.user_home, ".gem", expired_cert_file)

    Gem::Security.write(expired_cert, new_expired_cert_path)

    re_signed_cert = Gem::Security.re_sign(
      expired_cert,
      private_key,
      (Gem::Security::ONE_DAY * Gem.configuration.cert_expiration_length_days)
    )

    Gem::Security.write(re_signed_cert, expired_cert_path)

    yield(expired_cert_path, new_expired_cert_path) if block_given?
  end

  ##
  # Creates a new signer with an RSA +key+ or path to a key, and a certificate
  # +chain+ containing X509 certificates, encoding certificates or paths to
  # certificates.

  def initialize(key, cert_chain, passphrase = nil, options = {})
    @cert_chain = cert_chain
    @key        = key
    @passphrase = passphrase
    @options = DEFAULT_OPTIONS.merge(options)

    unless @key
      default_key = File.join Gem.default_key_path
      @key = default_key if File.exist? default_key
    end

    unless @cert_chain
      default_cert = File.join Gem.default_cert_path
      @cert_chain = [default_cert] if File.exist? default_cert
    end

    @digest_name      = Gem::Security::DIGEST_NAME
    @digest_algorithm = Gem::Security.create_digest(@digest_name)

    if @key && !@key.is_a?(OpenSSL::PKey::PKey)
      @key = OpenSSL::PKey.read(File.read(@key), @passphrase)
    end

    if @cert_chain
      @cert_chain = @cert_chain.compact.map do |cert|
        next cert if OpenSSL::X509::Certificate === cert

        cert = File.read cert if File.exist? cert

        OpenSSL::X509::Certificate.new cert
      end

      load_cert_chain
    end
  end

  ##
  # Extracts the full name of +cert+.  If the certificate has a subjectAltName
  # this value is preferred, otherwise the subject is used.

  def extract_name(cert) # :nodoc:
    subject_alt_name = cert.extensions.find {|e| "subjectAltName" == e.oid }

    if subject_alt_name
      /\Aemail:/ =~ subject_alt_name.value # rubocop:disable Performance/StartWith

      $' || subject_alt_name.value
    else
      cert.subject
    end
  end

  ##
  # Loads any missing issuers in the cert chain from the trusted certificates.
  #
  # If the issuer does not exist it is ignored as it will be checked later.

  def load_cert_chain # :nodoc:
    return if @cert_chain.empty?

    while @cert_chain.first.issuer.to_s != @cert_chain.first.subject.to_s do
      issuer = Gem::Security.trust_dir.issuer_of @cert_chain.first

      break unless issuer # cert chain is verified later

      @cert_chain.unshift issuer
    end
  end

  ##
  # Sign data with given digest algorithm

  def sign(data)
    return unless @key

    raise Gem::Security::Exception, "no certs provided" if @cert_chain.empty?

    if @cert_chain.length == 1 && @cert_chain.last.not_after < Time.now
      alert("Your certificate has expired, trying to re-sign it...")

      re_sign_key(
        expiration_length: (Gem::Security::ONE_DAY * options[:expiration_length_days])
      )
    end

    full_name = extract_name @cert_chain.last

    Gem::Security::SigningPolicy.verify @cert_chain, @key, {}, {}, full_name

    @key.sign @digest_algorithm.new, data
  end

  ##
  # Attempts to re-sign the private key if the signing certificate is expired.
  #
  # The key will be re-signed if:
  # * The expired certificate is self-signed
  # * The expired certificate is saved at ~/.gem/gem-public_cert.pem
  #   and the private key is saved at ~/.gem/gem-private_key.pem
  # * There is no file matching the expiry date at
  #   ~/.gem/gem-public_cert.pem.expired.%Y%m%d%H%M%S
  #
  # If the signing certificate can be re-signed the expired certificate will
  # be saved as ~/.gem/gem-public_cert.pem.expired.%Y%m%d%H%M%S where the
  # expiry time (not after) is used for the timestamp.

  def re_sign_key(expiration_length: Gem::Security::ONE_YEAR) # :nodoc:
    old_cert = @cert_chain.last

    disk_cert_path = File.join(Gem.default_cert_path)
    disk_cert = File.read(disk_cert_path) rescue nil

    disk_key_path = File.join(Gem.default_key_path)
    disk_key = OpenSSL::PKey.read(File.read(disk_key_path), @passphrase) rescue nil

    return unless disk_key

    if disk_key.to_pem == @key.to_pem && disk_cert == old_cert.to_pem
      expiry = old_cert.not_after.strftime("%Y%m%d%H%M%S")
      old_cert_file = "gem-public_cert.pem.expired.#{expiry}"
      old_cert_path = File.join(Gem.user_home, ".gem", old_cert_file)

      unless File.exist?(old_cert_path)
        Gem::Security.write(old_cert, old_cert_path)

        cert = Gem::Security.re_sign(old_cert, @key, expiration_length)

        Gem::Security.write(cert, disk_cert_path)

        alert("Your cert: #{disk_cert_path} has been auto re-signed with the key: #{disk_key_path}")
        alert("Your expired cert will be located at: #{old_cert_path}")

        @cert_chain = [cert]
      end
    end
  end
end
