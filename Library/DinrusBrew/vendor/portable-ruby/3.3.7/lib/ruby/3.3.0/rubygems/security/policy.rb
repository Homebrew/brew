# frozen_string_literal: true

require_relative "../user_interaction"

##
# A Gem::Security::Policy object encapsulates the settings for verifying
# signed gem files.  This is the base class.  You can either declare an
# instance of this or use one of the preset security policies in
# Gem::Security::Policies.

class Gem::Security::Policy
  include Gem::UserInteraction

  attr_reader :name

  attr_accessor :only_signed
  attr_accessor :only_trusted
  attr_accessor :verify_chain
  attr_accessor :verify_data
  attr_accessor :verify_root
  attr_accessor :verify_signer

  ##
  # Create a new Gem::Security::Policy object with the given mode and
  # options.

  def initialize(name, policy = {}, opt = {})
    @name = name

    @opt = opt

    # Default to security
    @only_signed   = true
    @only_trusted  = true
    @verify_chain  = true
    @verify_data   = true
    @verify_root   = true
    @verify_signer = true

    policy.each_pair do |key, val|
      case key
      when :verify_data   then @verify_data   = val
      when :verify_signer then @verify_signer = val
      when :verify_chain  then @verify_chain  = val
      when :verify_root   then @verify_root   = val
      when :only_trusted  then @only_trusted  = val
      when :only_signed   then @only_signed   = val
      end
    end
  end

  ##
  # Verifies each certificate in +chain+ has signed the following certificate
  # and is valid for the given +time+.

  def check_chain(chain, time)
    raise Gem::Security::Exception, "missing signing chain" unless chain
    raise Gem::Security::Exception, "empty signing chain" if chain.empty?

    begin
      chain.each_cons 2 do |issuer, cert|
        check_cert cert, issuer, time
      end

      true
    rescue Gem::Security::Exception => e
      raise Gem::Security::Exception, "invalid signing chain: #{e.message}"
    end
  end

  ##
  # Verifies that +data+ matches the +signature+ created by +public_key+ and
  # the +digest+ algorithm.

  def check_data(public_key, digest, signature, data)
    raise Gem::Security::Exception, "invalid signature" unless
      public_key.verify digest, signature, data.digest

    true
  end

  ##
  # Ensures that +signer+ is valid for +time+ and was signed by the +issuer+.
  # If the +issuer+ is +nil+ no verification is performed.

  def check_cert(signer, issuer, time)
    raise Gem::Security::Exception, "missing signing certificate" unless
      signer

    message = "certificate #{signer.subject}"

    if (not_before = signer.not_before) && not_before > time
      raise Gem::Security::Exception,
            "#{message} not valid before #{not_before}"
    end

    if (not_after = signer.not_after) && not_after < time
      raise Gem::Security::Exception, "#{message} not valid after #{not_after}"
    end

    if issuer && !signer.verify(issuer.public_key)
      raise Gem::Security::Exception,
            "#{message} was not issued by #{issuer.subject}"
    end

    true
  end

  ##
  # Ensures the public key of +key+ matches the public key in +signer+

  def check_key(signer, key)
    unless signer && key
      return true unless @only_signed

      raise Gem::Security::Exception, "missing key or signature"
    end

    raise Gem::Security::Exception,
      "certificate #{signer.subject} does not match the signing key" unless
        signer.check_private_key(key)

    true
  end

  ##
  # Ensures the root certificate in +chain+ is self-signed and valid for
  # +time+.

  def check_root(chain, time)
    raise Gem::Security::Exception, "missing signing chain" unless chain

    root = chain.first

    raise Gem::Security::Exception, "missing root certificate" unless root

    raise Gem::Security::Exception,
          "root certificate #{root.subject} is not self-signed " \
          "(issuer #{root.issuer})" if
      root.issuer != root.subject

    check_cert root, root, time
  end

  ##
  # Ensures the root of +chain+ has a trusted certificate in +trust_dir+ and
  # the digests of the two certificates match according to +digester+

  def check_trust(chain, digester, trust_dir)
    raise Gem::Security::Exception, "missing signing chain" unless chain

    root = chain.first

    raise Gem::Security::Exception, "missing root certificate" unless root

    path = Gem::Security.trust_dir.cert_path root

    unless File.exist? path
      message = "root cert #{root.subject} is not trusted".dup

      message << " (root of signing cert #{chain.last.subject})" if
        chain.length > 1

      raise Gem::Security::Exception, message
    end

    save_cert = OpenSSL::X509::Certificate.new File.read path
    save_dgst = digester.digest save_cert.public_key.to_pem

    pkey_str = root.public_key.to_pem
    cert_dgst = digester.digest pkey_str

    raise Gem::Security::Exception,
          "trusted root certificate #{root.subject} checksum " \
          "does not match signing root certificate checksum" unless
      save_dgst == cert_dgst

    true
  end

  ##
  # Extracts the email or subject from +certificate+

  def subject(certificate) # :nodoc:
    certificate.extensions.each do |extension|
      next unless extension.oid == "subjectAltName"

      return extension.value
    end

    certificate.subject.to_s
  end

  def inspect # :nodoc:
    format("[Policy: %s - data: %p signer: %p chain: %p root: %p " \
     "signed-only: %p trusted-only: %p]", @name, @verify_chain, @verify_data, @verify_root, @verify_signer, @only_signed, @only_trusted)
  end

  ##
  # For +full_name+, verifies the certificate +chain+ is valid, the +digests+
  # match the signatures +signatures+ created by the signer depending on the
  # +policy+ settings.
  #
  # If +key+ is given it is used to validate the signing certificate.

  def verify(chain, key = nil, digests = {}, signatures = {}, full_name = "(unknown)")
    if signatures.empty?
      if @only_signed
        raise Gem::Security::Exception,
          "unsigned gems are not allowed by the #{name} policy"
      elsif digests.empty?
        # lack of signatures is irrelevant if there is nothing to check
        # against
      else
        alert_warning "#{full_name} is not signed"
        return
      end
    end

    opt       = @opt
    digester  = Gem::Security.create_digest
    trust_dir = opt[:trust_dir]
    time      = Time.now

    _, signer_digests = digests.find do |_algorithm, file_digests|
      file_digests.values.first.name == Gem::Security::DIGEST_NAME
    end

    if @verify_data
      raise Gem::Security::Exception, "no digests provided (probable bug)" if
        signer_digests.nil? || signer_digests.empty?
    else
      signer_digests = {}
    end

    signer = chain.last

    check_key signer, key if key

    check_cert signer, nil, time if @verify_signer

    check_chain chain, time if @verify_chain

    check_root chain, time if @verify_root

    if @only_trusted
      check_trust chain, digester, trust_dir
    elsif signatures.empty? && digests.empty?
      # trust is irrelevant if there's no signatures to verify
    else
      alert_warning "#{subject signer} is not trusted for #{full_name}"
    end

    signatures.each do |file, _|
      digest = signer_digests[file]

      raise Gem::Security::Exception, "missing digest for #{file}" unless
        digest
    end

    signer_digests.each do |file, digest|
      signature = signatures[file]

      raise Gem::Security::Exception, "missing signature for #{file}" unless
        signature

      check_data signer.public_key, digester, signature, digest if @verify_data
    end

    true
  end

  ##
  # Extracts the certificate chain from the +spec+ and calls #verify to ensure
  # the signatures and certificate chain is valid according to the policy..

  def verify_signatures(spec, digests, signatures)
    chain = spec.cert_chain.map do |cert_pem|
      OpenSSL::X509::Certificate.new cert_pem
    end

    verify chain, nil, digests, signatures, spec.full_name

    true
  end

  alias_method :to_s, :name # :nodoc:
end
