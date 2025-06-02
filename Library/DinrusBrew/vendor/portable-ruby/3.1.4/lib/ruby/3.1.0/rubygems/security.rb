# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require_relative "exceptions"
require_relative "openssl"

##
# = Signing gems
#
# The Gem::Security implements cryptographic signatures for gems.  The section
# below is a step-by-step guide to using signed gems and generating your own.
#
# == Walkthrough
#
# === Building your certificate
#
# In order to start signing your gems, you'll need to build a private key and
# a self-signed certificate.  Here's how:
#
#   # build a private key and certificate for yourself:
#   $ gem cert --build you@example.com
#
# This could take anywhere from a few seconds to a minute or two, depending on
# the speed of your computer (public key algorithms aren't exactly the
# speediest crypto algorithms in the world).  When it's finished, you'll see
# the files "gem-private_key.pem" and "gem-public_cert.pem" in the current
# directory.
#
# First things first: Move both files to ~/.gem if you don't already have a
# key and certificate in that directory.  Ensure the file permissions make the
# key unreadable by others (by default the file is saved securely).
#
# Keep your private key hidden; if it's compromised, someone can sign packages
# as you (note: PKI has ways of mitigating the risk of stolen keys; more on
# that later).
#
# === Signing Gems
#
# In RubyGems 2 and newer there is no extra work to sign a gem.  RubyGems will
# automatically find your key and certificate in your home directory and use
# them to sign newly packaged gems.
#
# If your certificate is not self-signed (signed by a third party) RubyGems
# will attempt to load the certificate chain from the trusted certificates.
# Use <code>gem cert --add signing_cert.pem</code> to add your signers as
# trusted certificates.  See below for further information on certificate
# chains.
#
# If you build your gem it will automatically be signed.  If you peek inside
# your gem file, you'll see a couple of new files have been added:
#
#   $ tar tf your-gem-1.0.gem
#   metadata.gz
#   metadata.gz.sig # metadata signature
#   data.tar.gz
#   data.tar.gz.sig # data signature
#   checksums.yaml.gz
#   checksums.yaml.gz.sig # checksums signature
#
# === Manually signing gems
#
# If you wish to store your key in a separate secure location you'll need to
# set your gems up for signing by hand.  To do this, set the
# <code>signing_key</code> and <code>cert_chain</code> in the gemspec before
# packaging your gem:
#
#   s.signing_key = '/secure/path/to/gem-private_key.pem'
#   s.cert_chain = %w[/secure/path/to/gem-public_cert.pem]
#
# When you package your gem with these options set RubyGems will automatically
# load your key and certificate from the secure paths.
#
# === Signed gems and security policies
#
# Now let's verify the signature.  Go ahead and install the gem, but add the
# following options: <code>-P HighSecurity</code>, like this:
#
#   # install the gem with using the security policy "HighSecurity"
#   $ sudo gem install your.gem -P HighSecurity
#
# The <code>-P</code> option sets your security policy -- we'll talk about
# that in just a minute.  Eh, what's this?
#
#   $ gem install -P HighSecurity your-gem-1.0.gem
#   ERROR:  While executing gem ... (Gem::Security::Exception)
#       root cert /CN=you/DC=example is not trusted
#
# The culprit here is the security policy.  RubyGems has several different
# security policies.  Let's take a short break and go over the security
# policies.  Here's a list of the available security policies, and a brief
# description of each one:
#
# * NoSecurity - Well, no security at all.  Signed packages are treated like
#   unsigned packages.
# * LowSecurity - Pretty much no security.  If a package is signed then
#   RubyGems will make sure the signature matches the signing
#   certificate, and that the signing certificate hasn't expired, but
#   that's it.  A malicious user could easily circumvent this kind of
#   security.
# * MediumSecurity - Better than LowSecurity and NoSecurity, but still
#   fallible.  Package contents are verified against the signing
#   certificate, and the signing certificate is checked for validity,
#   and checked against the rest of the certificate chain (if you don't
#   know what a certificate chain is, stay tuned, we'll get to that).
#   The biggest improvement over LowSecurity is that MediumSecurity
#   won't install packages that are signed by untrusted sources.
#   Unfortunately, MediumSecurity still isn't totally secure -- a
#   malicious user can still unpack the gem, strip the signatures, and
#   distribute the gem unsigned.
# * HighSecurity - Here's the bugger that got us into this mess.
#   The HighSecurity policy is identical to the MediumSecurity policy,
#   except that it does not allow unsigned gems.  A malicious user
#   doesn't have a whole lot of options here; they can't modify the
#   package contents without invalidating the signature, and they can't
#   modify or remove signature or the signing certificate chain, or
#   RubyGems will simply refuse to install the package.  Oh well, maybe
#   they'll have better luck causing problems for CPAN users instead :).
#
# The reason RubyGems refused to install your shiny new signed gem was because
# it was from an untrusted source.  Well, your code is infallible (naturally),
# so you need to add yourself as a trusted source:
#
#   # add trusted certificate
#   gem cert --add ~/.gem/gem-public_cert.pem
#
# You've now added your public certificate as a trusted source.  Now you can
# install packages signed by your private key without any hassle.  Let's try
# the install command above again:
#
#   # install the gem with using the HighSecurity policy (and this time
#   # without any shenanigans)
#   $ gem install -P HighSecurity your-gem-1.0.gem
#   Successfully installed your-gem-1.0
#   1 gem installed
#
# This time RubyGems will accept your signed package and begin installing.
#
# While you're waiting for RubyGems to work it's magic, have a look at some of
# the other security commands by running <code>gem help cert</code>:
#
#   Options:
#     -a, --add CERT                   Add a trusted certificate.
#     -l, --list [FILTER]              List trusted certificates where the
#                                      subject contains FILTER
#     -r, --remove FILTER              Remove trusted certificates where the
#                                      subject contains FILTER
#     -b, --build EMAIL_ADDR           Build private key and self-signed
#                                      certificate for EMAIL_ADDR
#     -C, --certificate CERT           Signing certificate for --sign
#     -K, --private-key KEY            Key for --sign or --build
#     -A, --key-algorithm ALGORITHM    Select key algorithm for --build from RSA, DSA, or EC. Defaults to RSA.
#     -s, --sign CERT                  Signs CERT with the key from -K
#                                      and the certificate from -C
#     -d, --days NUMBER_OF_DAYS        Days before the certificate expires
#     -R, --re-sign                    Re-signs the certificate from -C with the key from -K
#
# We've already covered the <code>--build</code> option, and the
# <code>--add</code>, <code>--list</code>, and <code>--remove</code> commands
# seem fairly straightforward; they allow you to add, list, and remove the
# certificates in your trusted certificate list.  But what's with this
# <code>--sign</code> option?
#
# === Certificate chains
#
# To answer that question, let's take a look at "certificate chains", a
# concept I mentioned earlier.  There are a couple of problems with
# self-signed certificates: first of all, self-signed certificates don't offer
# a whole lot of security.  Sure, the certificate says Yukihiro Matsumoto, but
# how do I know it was actually generated and signed by matz himself unless he
# gave me the certificate in person?
#
# The second problem is scalability.  Sure, if there are 50 gem authors, then
# I have 50 trusted certificates, no problem.  What if there are 500 gem
# authors?  1000?  Having to constantly add new trusted certificates is a
# pain, and it actually makes the trust system less secure by encouraging
# RubyGems users to blindly trust new certificates.
#
# Here's where certificate chains come in.  A certificate chain establishes an
# arbitrarily long chain of trust between an issuing certificate and a child
# certificate.  So instead of trusting certificates on a per-developer basis,
# we use the PKI concept of certificate chains to build a logical hierarchy of
# trust.  Here's a hypothetical example of a trust hierarchy based (roughly)
# on geography:
#
#                         --------------------------
#                         | rubygems@rubygems.org |
#                         --------------------------
#                                     |
#                   -----------------------------------
#                   |                                 |
#       ----------------------------    -----------------------------
#       |  seattlerb@seattlerb.org |    | dcrubyists@richkilmer.com |
#       ----------------------------    -----------------------------
#            |                |                 |             |
#     ---------------   ----------------   -----------   --------------
#     |   drbrain   |   |   zenspider  |   | pabs@dc |   | tomcope@dc |
#     ---------------   ----------------   -----------   --------------
#
#
# Now, rather than having 4 trusted certificates (one for drbrain, zenspider,
# pabs@dc, and tomecope@dc), a user could actually get by with one
# certificate, the "rubygems@rubygems.org" certificate.
#
# Here's how it works:
#
# I install "rdoc-3.12.gem", a package signed by "drbrain".  I've never heard
# of "drbrain", but his certificate has a valid signature from the
# "seattle.rb@seattlerb.org" certificate, which in turn has a valid signature
# from the "rubygems@rubygems.org" certificate.  Voila!  At this point, it's
# much more reasonable for me to trust a package signed by "drbrain", because
# I can establish a chain to "rubygems@rubygems.org", which I do trust.
#
# === Signing certificates
#
# The <code>--sign</code> option allows all this to happen.  A developer
# creates their build certificate with the <code>--build</code> option, then
# has their certificate signed by taking it with them to their next regional
# Ruby meetup (in our hypothetical example), and it's signed there by the
# person holding the regional RubyGems signing certificate, which is signed at
# the next RubyConf by the holder of the top-level RubyGems certificate.  At
# each point the issuer runs the same command:
#
#   # sign a certificate with the specified key and certificate
#   # (note that this modifies client_cert.pem!)
#   $ gem cert -K /mnt/floppy/issuer-priv_key.pem -C issuer-pub_cert.pem
#      --sign client_cert.pem
#
# Then the holder of issued certificate (in this case, your buddy "drbrain"),
# can start using this signed certificate to sign RubyGems.  By the way, in
# order to let everyone else know about his new fancy signed certificate,
# "drbrain" would save his newly signed certificate as
# <code>~/.gem/gem-public_cert.pem</code>
#
# Obviously this RubyGems trust infrastructure doesn't exist yet.  Also, in
# the "real world", issuers actually generate the child certificate from a
# certificate request, rather than sign an existing certificate.  And our
# hypothetical infrastructure is missing a certificate revocation system.
# These are that can be fixed in the future...
#
# At this point you should know how to do all of these new and interesting
# things:
#
# * build a gem signing key and certificate
# * adjust your security policy
# * modify your trusted certificate list
# * sign a certificate
#
# == Manually verifying signatures
#
# In case you don't trust RubyGems you can verify gem signatures manually:
#
# 1. Fetch and unpack the gem
#
#      gem fetch some_signed_gem
#      tar -xf some_signed_gem-1.0.gem
#
# 2. Grab the public key from the gemspec
#
#      gem spec some_signed_gem-1.0.gem cert_chain | \
#        ruby -rpsych -e 'puts Psych.load($stdin)' > public_key.crt
#
# 3. Generate a SHA1 hash of the data.tar.gz
#
#      openssl dgst -sha1 < data.tar.gz > my.hash
#
# 4. Verify the signature
#
#      openssl rsautl -verify -inkey public_key.crt -certin \
#        -in data.tar.gz.sig > verified.hash
#
# 5. Compare your hash to the verified hash
#
#      diff -s verified.hash my.hash
#
# 6. Repeat 5 and 6 with metadata.gz
#
# == OpenSSL Reference
#
# The .pem files generated by --build and --sign are PEM files.  Here's a
# couple of useful OpenSSL commands for manipulating them:
#
#   # convert a PEM format X509 certificate into DER format:
#   # (note: Windows .cer files are X509 certificates in DER format)
#   $ openssl x509 -in input.pem -outform der -out output.der
#
#   # print out the certificate in a human-readable format:
#   $ openssl x509 -in input.pem -noout -text
#
# And you can do the same thing with the private key file as well:
#
#   # convert a PEM format RSA key into DER format:
#   $ openssl rsa -in input_key.pem -outform der -out output_key.der
#
#   # print out the key in a human readable format:
#   $ openssl rsa -in input_key.pem -noout -text
#
# == Bugs/TODO
#
# * There's no way to define a system-wide trust list.
# * custom security policies (from a YAML file, etc)
# * Simple method to generate a signed certificate request
# * Support for OCSP, SCVP, CRLs, or some other form of cert status check
#   (list is in order of preference)
# * Support for encrypted private keys
# * Some sort of semi-formal trust hierarchy (see long-winded explanation
#   above)
# * Path discovery (for gem certificate chains that don't have a self-signed
#   root) -- by the way, since we don't have this, THE ROOT OF THE CERTIFICATE
#   CHAIN MUST BE SELF SIGNED if Policy#verify_root is true (and it is for the
#   MediumSecurity and HighSecurity policies)
# * Better explanation of X509 naming (ie, we don't have to use email
#   addresses)
# * Honor AIA field (see note about OCSP above)
# * Honor extension restrictions
# * Might be better to store the certificate chain as a PKCS#7 or PKCS#12
#   file, instead of an array embedded in the metadata.
#
# == Original author
#
# Paul Duncan <pabs@pablotron.org>
# http://pablotron.org/

module Gem::Security

  ##
  # Gem::Security default exception type

  class Exception < Gem::Exception; end

  ##
  # Used internally to select the signing digest from all computed digests

  DIGEST_NAME = "SHA256" # :nodoc:

  ##
  # Length of keys created by RSA and DSA keys

  RSA_DSA_KEY_LENGTH = 3072

  ##
  # Default algorithm to use when building a key pair

  DEFAULT_KEY_ALGORITHM = "RSA"

  ##
  # Named curve used for Elliptic Curve

  EC_NAME = "secp384r1"

  ##
  # Cipher used to encrypt the key pair used to sign gems.
  # Must be in the list returned by OpenSSL::Cipher.ciphers

  KEY_CIPHER = OpenSSL::Cipher.new("AES-256-CBC") if defined?(OpenSSL::Cipher)

  ##
  # One day in seconds

  ONE_DAY = 86400

  ##
  # One year in seconds

  ONE_YEAR = ONE_DAY * 365

  ##
  # The default set of extensions are:
  #
  # * The certificate is not a certificate authority
  # * The key for the certificate may be used for key and data encipherment
  #   and digital signatures
  # * The certificate contains a subject key identifier

  EXTENSIONS = {
    "basicConstraints"     => "CA:FALSE",
    "keyUsage"             =>
      "keyEncipherment,dataEncipherment,digitalSignature",
    "subjectKeyIdentifier" => "hash",
  }.freeze

  def self.alt_name_or_x509_entry(certificate, x509_entry)
    alt_name = certificate.extensions.find do |extension|
      extension.oid == "#{x509_entry}AltName"
    end

    return alt_name.value if alt_name

    certificate.send x509_entry
  end

  ##
  # Creates an unsigned certificate for +subject+ and +key+.  The lifetime of
  # the key is from the current time to +age+ which defaults to one year.
  #
  # The +extensions+ restrict the key to the indicated uses.

  def self.create_cert(subject, key, age = ONE_YEAR, extensions = EXTENSIONS,
                       serial = 1)
    cert = OpenSSL::X509::Certificate.new

    cert.public_key = get_public_key(key)
    cert.version    = 2
    cert.serial     = serial

    cert.not_before = Time.now
    cert.not_after  = Time.now + age

    cert.subject    = subject

    ef = OpenSSL::X509::ExtensionFactory.new nil, cert

    cert.extensions = extensions.map do |ext_name, value|
      ef.create_extension ext_name, value
    end

    cert
  end

  ##
  # Gets the right public key from a PKey instance

  def self.get_public_key(key)
    # Ruby 3.0 (Ruby/OpenSSL 2.2) or later
    return OpenSSL::PKey.read(key.public_to_der) if key.respond_to?(:public_to_der)
    return key.public_key unless key.is_a?(OpenSSL::PKey::EC)

    ec_key = OpenSSL::PKey::EC.new(key.group.curve_name)
    ec_key.public_key = key.public_key
    ec_key
  end

  ##
  # In Ruby 2.3 EC doesn't implement the private_key? but not the private? method

  if defined?(OpenSSL::PKey::EC) && Gem::Version.new(String.new(RUBY_VERSION)) < Gem::Version.new("2.4.0")
    OpenSSL::PKey::EC.send(:alias_method, :private?, :private_key?)
  end

  ##
  # Creates a self-signed certificate with an issuer and subject from +email+,
  # a subject alternative name of +email+ and the given +extensions+ for the
  # +key+.

  def self.create_cert_email(email, key, age = ONE_YEAR, extensions = EXTENSIONS)
    subject = email_to_name email

    extensions = extensions.merge "subjectAltName" => "email:#{email}"

    create_cert_self_signed subject, key, age, extensions
  end

  ##
  # Creates a self-signed certificate with an issuer and subject of +subject+
  # and the given +extensions+ for the +key+.

  def self.create_cert_self_signed(subject, key, age = ONE_YEAR,
                                   extensions = EXTENSIONS, serial = 1)
    certificate = create_cert subject, key, age, extensions

    sign certificate, key, certificate, age, extensions, serial
  end

  ##
  # Creates a new digest instance using the specified +algorithm+. The default
  # is SHA256.

  if defined?(OpenSSL::Digest)
    def self.create_digest(algorithm = DIGEST_NAME)
      OpenSSL::Digest.new(algorithm)
    end
  else
    require "digest"

    def self.create_digest(algorithm = DIGEST_NAME)
      Digest.const_get(algorithm).new
    end
  end

  ##
  # Creates a new key pair of the specified +algorithm+. RSA, DSA, and EC
  # are supported.

  def self.create_key(algorithm)
    if defined?(OpenSSL::PKey)
      case algorithm.downcase
      when "dsa"
        OpenSSL::PKey::DSA.new(RSA_DSA_KEY_LENGTH)
      when "rsa"
        OpenSSL::PKey::RSA.new(RSA_DSA_KEY_LENGTH)
      when "ec"
        if RUBY_VERSION >= "2.4.0"
          OpenSSL::PKey::EC.generate(EC_NAME)
        else
          domain_key = OpenSSL::PKey::EC.new(EC_NAME)
          domain_key.generate_key
          domain_key
        end
      else
        raise Gem::Security::Exception,
        "#{algorithm} algorithm not found. RSA, DSA, and EC algorithms are supported."
      end
    end
  end

  ##
  # Turns +email_address+ into an OpenSSL::X509::Name

  def self.email_to_name(email_address)
    email_address = email_address.gsub(/[^\w@.-]+/i, "_")

    cn, dcs = email_address.split "@"

    dcs = dcs.split "."

    OpenSSL::X509::Name.new([
      ["CN", cn],
      *dcs.map {|dc| ["DC", dc] },
    ])
  end

  ##
  # Signs +expired_certificate+ with +private_key+ if the keys match and the
  # expired certificate was self-signed.
  #--
  # TODO increment serial

  def self.re_sign(expired_certificate, private_key, age = ONE_YEAR,
                   extensions = EXTENSIONS)
    raise Gem::Security::Exception,
          "incorrect signing key for re-signing " +
          "#{expired_certificate.subject}" unless
      expired_certificate.check_private_key(private_key)

    unless expired_certificate.subject.to_s ==
           expired_certificate.issuer.to_s
      subject = alt_name_or_x509_entry expired_certificate, :subject
      issuer  = alt_name_or_x509_entry expired_certificate, :issuer

      raise Gem::Security::Exception,
            "#{subject} is not self-signed, contact #{issuer} " +
            "to obtain a valid certificate"
    end

    serial = expired_certificate.serial + 1

    create_cert_self_signed(expired_certificate.subject, private_key, age,
                            extensions, serial)
  end

  ##
  # Resets the trust directory for verifying gems.

  def self.reset
    @trust_dir = nil
  end

  ##
  # Sign the public key from +certificate+ with the +signing_key+ and
  # +signing_cert+, using the Gem::Security::DIGEST_NAME.  Uses the
  # default certificate validity range and extensions.
  #
  # Returns the newly signed certificate.

  def self.sign(certificate, signing_key, signing_cert,
                age = ONE_YEAR, extensions = EXTENSIONS, serial = 1)
    signee_subject = certificate.subject
    signee_key     = certificate.public_key

    alt_name = certificate.extensions.find do |extension|
      extension.oid == "subjectAltName"
    end

    extensions = extensions.merge "subjectAltName" => alt_name.value if
      alt_name

    issuer_alt_name = signing_cert.extensions.find do |extension|
      extension.oid == "subjectAltName"
    end

    extensions = extensions.merge "issuerAltName" => issuer_alt_name.value if
      issuer_alt_name

    signed = create_cert signee_subject, signee_key, age, extensions, serial
    signed.issuer = signing_cert.subject

    signed.sign signing_key, Gem::Security::DIGEST_NAME
  end

  ##
  # Returns a Gem::Security::TrustDir which wraps the directory where trusted
  # certificates live.

  def self.trust_dir
    return @trust_dir if @trust_dir

    dir = File.join Gem.user_home, ".gem", "trust"

    @trust_dir ||= Gem::Security::TrustDir.new dir
  end

  ##
  # Enumerates the trusted certificates via Gem::Security::TrustDir.

  def self.trusted_certificates(&block)
    trust_dir.each_certificate(&block)
  end

  ##
  # Writes +pemmable+, which must respond to +to_pem+ to +path+ with the given
  # +permissions+. If passed +cipher+ and +passphrase+ those arguments will be
  # passed to +to_pem+.

  def self.write(pemmable, path, permissions = 0600, passphrase = nil, cipher = KEY_CIPHER)
    path = File.expand_path path

    File.open path, "wb", permissions do |io|
      if passphrase && cipher
        io.write pemmable.to_pem cipher, passphrase
      else
        io.write pemmable.to_pem
      end
    end

    path
  end

  reset

end

if Gem::HAVE_OPENSSL
  require_relative "security/policy"
  require_relative "security/policies"
  require_relative "security/trust_dir"
end

require_relative "security/signer"
