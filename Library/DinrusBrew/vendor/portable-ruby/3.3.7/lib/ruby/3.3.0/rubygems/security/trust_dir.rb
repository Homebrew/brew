# frozen_string_literal: true

##
# The TrustDir manages the trusted certificates for gem signature
# verification.

class Gem::Security::TrustDir
  ##
  # Default permissions for the trust directory and its contents

  DEFAULT_PERMISSIONS = {
    trust_dir: 0o700,
    trusted_cert: 0o600,
  }.freeze

  ##
  # The directory where trusted certificates will be stored.

  attr_reader :dir

  ##
  # Creates a new TrustDir using +dir+ where the directory and file
  # permissions will be checked according to +permissions+

  def initialize(dir, permissions = DEFAULT_PERMISSIONS)
    @dir = dir
    @permissions = permissions

    @digester = Gem::Security.create_digest
  end

  ##
  # Returns the path to the trusted +certificate+

  def cert_path(certificate)
    name_path certificate.subject
  end

  ##
  # Enumerates trusted certificates.

  def each_certificate
    return enum_for __method__ unless block_given?

    glob = File.join @dir, "*.pem"

    Dir[glob].each do |certificate_file|
      certificate = load_certificate certificate_file

      yield certificate, certificate_file
    rescue OpenSSL::X509::CertificateError
      next # HACK: warn
    end
  end

  ##
  # Returns the issuer certificate of the given +certificate+ if it exists in
  # the trust directory.

  def issuer_of(certificate)
    path = name_path certificate.issuer

    return unless File.exist? path

    load_certificate path
  end

  ##
  # Returns the path to the trusted certificate with the given ASN.1 +name+

  def name_path(name)
    digest = @digester.hexdigest name.to_s

    File.join @dir, "cert-#{digest}.pem"
  end

  ##
  # Loads the given +certificate_file+

  def load_certificate(certificate_file)
    pem = File.read certificate_file

    OpenSSL::X509::Certificate.new pem
  end

  ##
  # Add a certificate to trusted certificate list.

  def trust_cert(certificate)
    verify

    destination = cert_path certificate

    File.open destination, "wb", 0o600 do |io|
      io.write certificate.to_pem
      io.chmod(@permissions[:trusted_cert])
    end
  end

  ##
  # Make sure the trust directory exists.  If it does exist, make sure it's
  # actually a directory.  If not, then create it with the appropriate
  # permissions.

  def verify
    require "fileutils"
    if File.exist? @dir
      raise Gem::Security::Exception,
        "trust directory #{@dir} is not a directory" unless
          File.directory? @dir

      FileUtils.chmod 0o700, @dir
    else
      FileUtils.mkdir_p @dir, mode: @permissions[:trust_dir]
    end
  end
end
