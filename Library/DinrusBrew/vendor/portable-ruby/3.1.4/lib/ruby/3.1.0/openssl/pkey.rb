# frozen_string_literal: true
#--
# Ruby/OpenSSL Project
# Copyright (C) 2017 Ruby/OpenSSL Project Authors
#++

require_relative 'marshal'

module OpenSSL::PKey
  class DH
    include OpenSSL::Marshal

    # :call-seq:
    #    dh.public_key -> dhnew
    #
    # Returns a new DH instance that carries just the \DH parameters.
    #
    # Contrary to the method name, the returned DH object contains only
    # parameters and not the public key.
    #
    # This method is provided for backwards compatibility. In most cases, there
    # is no need to call this method.
    #
    # For the purpose of re-generating the key pair while keeping the
    # parameters, check OpenSSL::PKey.generate_key.
    #
    # Example:
    #   # OpenSSL::PKey::DH.generate by default generates a random key pair
    #   dh1 = OpenSSL::PKey::DH.generate(2048)
    #   p dh1.priv_key #=> #<OpenSSL::BN 1288347...>
    #   dhcopy = dh1.public_key
    #   p dhcopy.priv_key #=> nil
    def public_key
      DH.new(to_der)
    end

    # :call-seq:
    #    dh.compute_key(pub_bn) -> string
    #
    # Returns a String containing a shared secret computed from the other
    # party's public value.
    #
    # This method is provided for backwards compatibility, and calls #derive
    # internally.
    #
    # === Parameters
    # * _pub_bn_ is a OpenSSL::BN, *not* the DH instance returned by
    #   DH#public_key as that contains the DH parameters only.
    def compute_key(pub_bn)
      # FIXME: This is constructing an X.509 SubjectPublicKeyInfo and is very
      # inefficient
      obj = OpenSSL::ASN1.Sequence([
        OpenSSL::ASN1.Sequence([
          OpenSSL::ASN1.ObjectId("dhKeyAgreement"),
          OpenSSL::ASN1.Sequence([
            OpenSSL::ASN1.Integer(p),
            OpenSSL::ASN1.Integer(g),
          ]),
        ]),
        OpenSSL::ASN1.BitString(OpenSSL::ASN1.Integer(pub_bn).to_der),
      ])
      derive(OpenSSL::PKey.read(obj.to_der))
    end

    # :call-seq:
    #    dh.generate_key! -> self
    #
    # Generates a private and public key unless a private key already exists.
    # If this DH instance was generated from public \DH parameters (e.g. by
    # encoding the result of DH#public_key), then this method needs to be
    # called first in order to generate the per-session keys before performing
    # the actual key exchange.
    #
    # <b>Deprecated in version 3.0</b>. This method is incompatible with
    # OpenSSL 3.0.0 or later.
    #
    # See also OpenSSL::PKey.generate_key.
    #
    # Example:
    #   # DEPRECATED USAGE: This will not work on OpenSSL 3.0 or later
    #   dh0 = OpenSSL::PKey::DH.new(2048)
    #   dh = dh0.public_key # #public_key only copies the DH parameters (contrary to the name)
    #   dh.generate_key!
    #   puts dh.private? # => true
    #   puts dh0.pub_key == dh.pub_key #=> false
    #
    #   # With OpenSSL::PKey.generate_key
    #   dh0 = OpenSSL::PKey::DH.new(2048)
    #   dh = OpenSSL::PKey.generate_key(dh0)
    #   puts dh0.pub_key == dh.pub_key #=> false
    def generate_key!
      if OpenSSL::OPENSSL_VERSION_NUMBER >= 0x30000000
        raise DHError, "OpenSSL::PKey::DH is immutable on OpenSSL 3.0; " \
        "use OpenSSL::PKey.generate_key instead"
      end

      unless priv_key
        tmp = OpenSSL::PKey.generate_key(self)
        set_key(tmp.pub_key, tmp.priv_key)
      end
      self
    end

    class << self
      # :call-seq:
      #    DH.generate(size, generator = 2) -> dh
      #
      # Creates a new DH instance from scratch by generating random parameters
      # and a key pair.
      #
      # See also OpenSSL::PKey.generate_parameters and
      # OpenSSL::PKey.generate_key.
      #
      # +size+::
      #   The desired key size in bits.
      # +generator+::
      #   The generator.
      def generate(size, generator = 2, &blk)
        dhparams = OpenSSL::PKey.generate_parameters("DH", {
          "dh_paramgen_prime_len" => size,
          "dh_paramgen_generator" => generator,
        }, &blk)
        OpenSSL::PKey.generate_key(dhparams)
      end

      # Handle DH.new(size, generator) form here; new(str) and new() forms
      # are handled by #initialize
      def new(*args, &blk) # :nodoc:
        if args[0].is_a?(Integer)
          generate(*args, &blk)
        else
          super
        end
      end
    end
  end

  class DSA
    include OpenSSL::Marshal

    # :call-seq:
    #    dsa.public_key -> dsanew
    #
    # Returns a new DSA instance that carries just the \DSA parameters and the
    # public key.
    #
    # This method is provided for backwards compatibility. In most cases, there
    # is no need to call this method.
    #
    # For the purpose of serializing the public key, to PEM or DER encoding of
    # X.509 SubjectPublicKeyInfo format, check PKey#public_to_pem and
    # PKey#public_to_der.
    def public_key
      OpenSSL::PKey.read(public_to_der)
    end

    class << self
      # :call-seq:
      #    DSA.generate(size) -> dsa
      #
      # Creates a new DSA instance by generating a private/public key pair
      # from scratch.
      #
      # See also OpenSSL::PKey.generate_parameters and
      # OpenSSL::PKey.generate_key.
      #
      # +size+::
      #   The desired key size in bits.
      def generate(size, &blk)
        # FIPS 186-4 specifies four (L,N) pairs: (1024,160), (2048,224),
        # (2048,256), and (3072,256).
        #
        # q size is derived here with compatibility with
        # DSA_generator_parameters_ex() which previous versions of ruby/openssl
        # used to call.
        qsize = size >= 2048 ? 256 : 160
        dsaparams = OpenSSL::PKey.generate_parameters("DSA", {
          "dsa_paramgen_bits" => size,
          "dsa_paramgen_q_bits" => qsize,
        }, &blk)
        OpenSSL::PKey.generate_key(dsaparams)
      end

      # Handle DSA.new(size) form here; new(str) and new() forms
      # are handled by #initialize
      def new(*args, &blk) # :nodoc:
        if args[0].is_a?(Integer)
          generate(*args, &blk)
        else
          super
        end
      end
    end

    # :call-seq:
    #    dsa.syssign(string) -> string
    #
    # Computes and returns the \DSA signature of +string+, where +string+ is
    # expected to be an already-computed message digest of the original input
    # data. The signature is issued using the private key of this DSA instance.
    #
    # <b>Deprecated in version 3.0</b>.
    # Consider using PKey::PKey#sign_raw and PKey::PKey#verify_raw instead.
    #
    # +string+::
    #   A message digest of the original input data to be signed.
    #
    # Example:
    #   dsa = OpenSSL::PKey::DSA.new(2048)
    #   doc = "Sign me"
    #   digest = OpenSSL::Digest.digest('SHA1', doc)
    #
    #   # With legacy #syssign and #sysverify:
    #   sig = dsa.syssign(digest)
    #   p dsa.sysverify(digest, sig) #=> true
    #
    #   # With #sign_raw and #verify_raw:
    #   sig = dsa.sign_raw(nil, digest)
    #   p dsa.verify_raw(nil, sig, digest) #=> true
    def syssign(string)
      q or raise OpenSSL::PKey::DSAError, "incomplete DSA"
      private? or raise OpenSSL::PKey::DSAError, "Private DSA key needed!"
      begin
        sign_raw(nil, string)
      rescue OpenSSL::PKey::PKeyError
        raise OpenSSL::PKey::DSAError, $!.message
      end
    end

    # :call-seq:
    #    dsa.sysverify(digest, sig) -> true | false
    #
    # Verifies whether the signature is valid given the message digest input.
    # It does so by validating +sig+ using the public key of this DSA instance.
    #
    # <b>Deprecated in version 3.0</b>.
    # Consider using PKey::PKey#sign_raw and PKey::PKey#verify_raw instead.
    #
    # +digest+::
    #   A message digest of the original input data to be signed.
    # +sig+::
    #   A \DSA signature value.
    def sysverify(digest, sig)
      verify_raw(nil, sig, digest)
    rescue OpenSSL::PKey::PKeyError
      raise OpenSSL::PKey::DSAError, $!.message
    end
  end

  if defined?(EC)
  class EC
    include OpenSSL::Marshal

    # :call-seq:
    #    key.dsa_sign_asn1(data) -> String
    #
    # <b>Deprecated in version 3.0</b>.
    # Consider using PKey::PKey#sign_raw and PKey::PKey#verify_raw instead.
    def dsa_sign_asn1(data)
      sign_raw(nil, data)
    rescue OpenSSL::PKey::PKeyError
      raise OpenSSL::PKey::ECError, $!.message
    end

    # :call-seq:
    #    key.dsa_verify_asn1(data, sig) -> true | false
    #
    # <b>Deprecated in version 3.0</b>.
    # Consider using PKey::PKey#sign_raw and PKey::PKey#verify_raw instead.
    def dsa_verify_asn1(data, sig)
      verify_raw(nil, sig, data)
    rescue OpenSSL::PKey::PKeyError
      raise OpenSSL::PKey::ECError, $!.message
    end

    # :call-seq:
    #    ec.dh_compute_key(pubkey) -> string
    #
    # Derives a shared secret by ECDH. _pubkey_ must be an instance of
    # OpenSSL::PKey::EC::Point and must belong to the same group.
    #
    # This method is provided for backwards compatibility, and calls #derive
    # internally.
    def dh_compute_key(pubkey)
      obj = OpenSSL::ASN1.Sequence([
        OpenSSL::ASN1.Sequence([
          OpenSSL::ASN1.ObjectId("id-ecPublicKey"),
          group.to_der,
        ]),
        OpenSSL::ASN1.BitString(pubkey.to_octet_string(:uncompressed)),
      ])
      derive(OpenSSL::PKey.read(obj.to_der))
    end
  end

  class EC::Point
    # :call-seq:
    #    point.to_bn([conversion_form]) -> OpenSSL::BN
    #
    # Returns the octet string representation of the EC point as an instance of
    # OpenSSL::BN.
    #
    # If _conversion_form_ is not given, the _point_conversion_form_ attribute
    # set to the group is used.
    #
    # See #to_octet_string for more information.
    def to_bn(conversion_form = group.point_conversion_form)
      OpenSSL::BN.new(to_octet_string(conversion_form), 2)
    end
  end
  end

  class RSA
    include OpenSSL::Marshal

    # :call-seq:
    #    rsa.public_key -> rsanew
    #
    # Returns a new RSA instance that carries just the public key components.
    #
    # This method is provided for backwards compatibility. In most cases, there
    # is no need to call this method.
    #
    # For the purpose of serializing the public key, to PEM or DER encoding of
    # X.509 SubjectPublicKeyInfo format, check PKey#public_to_pem and
    # PKey#public_to_der.
    def public_key
      OpenSSL::PKey.read(public_to_der)
    end

    class << self
      # :call-seq:
      #    RSA.generate(size, exponent = 65537) -> RSA
      #
      # Generates an \RSA keypair.
      #
      # See also OpenSSL::PKey.generate_key.
      #
      # +size+::
      #   The desired key size in bits.
      # +exponent+::
      #   An odd Integer, normally 3, 17, or 65537.
      def generate(size, exp = 0x10001, &blk)
        OpenSSL::PKey.generate_key("RSA", {
          "rsa_keygen_bits" => size,
          "rsa_keygen_pubexp" => exp,
        }, &blk)
      end

      # Handle RSA.new(size, exponent) form here; new(str) and new() forms
      # are handled by #initialize
      def new(*args, &blk) # :nodoc:
        if args[0].is_a?(Integer)
          generate(*args, &blk)
        else
          super
        end
      end
    end

    # :call-seq:
    #    rsa.private_encrypt(string)          -> String
    #    rsa.private_encrypt(string, padding) -> String
    #
    # Encrypt +string+ with the private key.  +padding+ defaults to
    # PKCS1_PADDING. The encrypted string output can be decrypted using
    # #public_decrypt.
    #
    # <b>Deprecated in version 3.0</b>.
    # Consider using PKey::PKey#sign_raw and PKey::PKey#verify_raw, and
    # PKey::PKey#verify_recover instead.
    def private_encrypt(string, padding = PKCS1_PADDING)
      n or raise OpenSSL::PKey::RSAError, "incomplete RSA"
      private? or raise OpenSSL::PKey::RSAError, "private key needed."
      begin
        sign_raw(nil, string, {
          "rsa_padding_mode" => translate_padding_mode(padding),
        })
      rescue OpenSSL::PKey::PKeyError
        raise OpenSSL::PKey::RSAError, $!.message
      end
    end

    # :call-seq:
    #    rsa.public_decrypt(string)          -> String
    #    rsa.public_decrypt(string, padding) -> String
    #
    # Decrypt +string+, which has been encrypted with the private key, with the
    # public key.  +padding+ defaults to PKCS1_PADDING.
    #
    # <b>Deprecated in version 3.0</b>.
    # Consider using PKey::PKey#sign_raw and PKey::PKey#verify_raw, and
    # PKey::PKey#verify_recover instead.
    def public_decrypt(string, padding = PKCS1_PADDING)
      n or raise OpenSSL::PKey::RSAError, "incomplete RSA"
      begin
        verify_recover(nil, string, {
          "rsa_padding_mode" => translate_padding_mode(padding),
        })
      rescue OpenSSL::PKey::PKeyError
        raise OpenSSL::PKey::RSAError, $!.message
      end
    end

    # :call-seq:
    #    rsa.public_encrypt(string)          -> String
    #    rsa.public_encrypt(string, padding) -> String
    #
    # Encrypt +string+ with the public key.  +padding+ defaults to
    # PKCS1_PADDING. The encrypted string output can be decrypted using
    # #private_decrypt.
    #
    # <b>Deprecated in version 3.0</b>.
    # Consider using PKey::PKey#encrypt and PKey::PKey#decrypt instead.
    def public_encrypt(data, padding = PKCS1_PADDING)
      n or raise OpenSSL::PKey::RSAError, "incomplete RSA"
      begin
        encrypt(data, {
          "rsa_padding_mode" => translate_padding_mode(padding),
        })
      rescue OpenSSL::PKey::PKeyError
        raise OpenSSL::PKey::RSAError, $!.message
      end
    end

    # :call-seq:
    #    rsa.private_decrypt(string)          -> String
    #    rsa.private_decrypt(string, padding) -> String
    #
    # Decrypt +string+, which has been encrypted with the public key, with the
    # private key. +padding+ defaults to PKCS1_PADDING.
    #
    # <b>Deprecated in version 3.0</b>.
    # Consider using PKey::PKey#encrypt and PKey::PKey#decrypt instead.
    def private_decrypt(data, padding = PKCS1_PADDING)
      n or raise OpenSSL::PKey::RSAError, "incomplete RSA"
      private? or raise OpenSSL::PKey::RSAError, "private key needed."
      begin
        decrypt(data, {
          "rsa_padding_mode" => translate_padding_mode(padding),
        })
      rescue OpenSSL::PKey::PKeyError
        raise OpenSSL::PKey::RSAError, $!.message
      end
    end

    PKCS1_PADDING = 1
    SSLV23_PADDING = 2
    NO_PADDING = 3
    PKCS1_OAEP_PADDING = 4

    private def translate_padding_mode(num)
      case num
      when PKCS1_PADDING
        "pkcs1"
      when SSLV23_PADDING
        "sslv23"
      when NO_PADDING
        "none"
      when PKCS1_OAEP_PADDING
        "oaep"
      else
        raise OpenSSL::PKey::PKeyError, "unsupported padding mode"
      end
    end
  end
end
