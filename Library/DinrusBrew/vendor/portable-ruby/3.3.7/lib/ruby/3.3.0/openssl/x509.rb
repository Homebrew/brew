# frozen_string_literal: true
#--
# = Ruby-space definitions that completes C-space funcs for X509 and subclasses
#
# = Info
# 'OpenSSL for Ruby 2' project
# Copyright (C) 2002  Michal Rokos <m.rokos@sh.cvut.cz>
# All rights reserved.
#
# = Licence
# This program is licensed under the same licence as Ruby.
# (See the file 'LICENCE'.)
#++

require_relative 'marshal'

module OpenSSL
  module X509
    class ExtensionFactory
      def create_extension(*arg)
        if arg.size > 1
          create_ext(*arg)
        else
          send("create_ext_from_"+arg[0].class.name.downcase, arg[0])
        end
      end

      def create_ext_from_array(ary)
        raise ExtensionError, "unexpected array form" if ary.size > 3
        create_ext(ary[0], ary[1], ary[2])
      end

      def create_ext_from_string(str) # "oid = critical, value"
        oid, value = str.split(/=/, 2)
        oid.strip!
        value.strip!
        create_ext(oid, value)
      end

      def create_ext_from_hash(hash)
        create_ext(hash["oid"], hash["value"], hash["critical"])
      end
    end

    class Extension
      include OpenSSL::Marshal

      def ==(other)
        return false unless Extension === other
        to_der == other.to_der
      end

      def to_s # "oid = critical, value"
        str = self.oid
        str << " = "
        str << "critical, " if self.critical?
        str << self.value.gsub(/\n/, ", ")
      end

      def to_h # {"oid"=>sn|ln, "value"=>value, "critical"=>true|false}
        {"oid"=>self.oid,"value"=>self.value,"critical"=>self.critical?}
      end

      def to_a
        [ self.oid, self.value, self.critical? ]
      end

      module Helpers
        def find_extension(oid)
          extensions.find { |e| e.oid == oid }
        end
      end

      module SubjectKeyIdentifier
        include Helpers

        # Get the subject's key identifier from the subjectKeyIdentifier
        # exteension, as described in RFC5280 Section 4.2.1.2.
        #
        # Returns the binary String key identifier or nil or raises
        # ASN1::ASN1Error.
        def subject_key_identifier
          ext = find_extension("subjectKeyIdentifier")
          return nil if ext.nil?

          ski_asn1 = ASN1.decode(ext.value_der)
          if ext.critical? || ski_asn1.tag_class != :UNIVERSAL || ski_asn1.tag != ASN1::OCTET_STRING
            raise ASN1::ASN1Error, "invalid extension"
          end

          ski_asn1.value
        end
      end

      module AuthorityKeyIdentifier
        include Helpers

        # Get the issuing certificate's key identifier from the
        # authorityKeyIdentifier extension, as described in RFC5280
        # Section 4.2.1.1
        #
        # Returns the binary String keyIdentifier or nil or raises
        # ASN1::ASN1Error.
        def authority_key_identifier
          ext = find_extension("authorityKeyIdentifier")
          return nil if ext.nil?

          aki_asn1 = ASN1.decode(ext.value_der)
          if ext.critical? || aki_asn1.tag_class != :UNIVERSAL || aki_asn1.tag != ASN1::SEQUENCE
            raise ASN1::ASN1Error, "invalid extension"
          end

          key_id = aki_asn1.value.find do |v|
            v.tag_class == :CONTEXT_SPECIFIC && v.tag == 0
          end

          key_id.nil? ? nil : key_id.value
        end
      end

      module CRLDistributionPoints
        include Helpers

        # Get the distributionPoint fullName URI from the certificate's CRL
        # distribution points extension, as described in RFC5280 Section
        # 4.2.1.13
        #
        # Returns an array of strings or nil or raises ASN1::ASN1Error.
        def crl_uris
          ext = find_extension("crlDistributionPoints")
          return nil if ext.nil?

          cdp_asn1 = ASN1.decode(ext.value_der)
          if cdp_asn1.tag_class != :UNIVERSAL || cdp_asn1.tag != ASN1::SEQUENCE
            raise ASN1::ASN1Error, "invalid extension"
          end

          crl_uris = cdp_asn1.map do |crl_distribution_point|
            distribution_point = crl_distribution_point.value.find do |v|
              v.tag_class == :CONTEXT_SPECIFIC && v.tag == 0
            end
            full_name = distribution_point&.value&.find do |v|
              v.tag_class == :CONTEXT_SPECIFIC && v.tag == 0
            end
            full_name&.value&.find do |v|
              v.tag_class == :CONTEXT_SPECIFIC && v.tag == 6 # uniformResourceIdentifier
            end
          end

          crl_uris&.map(&:value)
        end
      end

      module AuthorityInfoAccess
        include Helpers

        # Get the information and services for the issuer from the certificate's
        # authority information access extension exteension, as described in RFC5280
        # Section 4.2.2.1.
        #
        # Returns an array of strings or nil or raises ASN1::ASN1Error.
        def ca_issuer_uris
          aia_asn1 = parse_aia_asn1
          return nil if aia_asn1.nil?

          ca_issuer = aia_asn1.value.select do |authority_info_access|
            authority_info_access.value.first.value == "caIssuers"
          end

          ca_issuer&.map(&:value)&.map(&:last)&.map(&:value)
        end

        # Get the URIs for OCSP from the certificate's authority information access
        # extension exteension, as described in RFC5280 Section 4.2.2.1.
        #
        # Returns an array of strings or nil or raises ASN1::ASN1Error.
        def ocsp_uris
          aia_asn1 = parse_aia_asn1
          return nil if aia_asn1.nil?

          ocsp = aia_asn1.value.select do |authority_info_access|
            authority_info_access.value.first.value == "OCSP"
          end

          ocsp&.map(&:value)&.map(&:last)&.map(&:value)
        end

        private

          def parse_aia_asn1
            ext = find_extension("authorityInfoAccess")
            return nil if ext.nil?

            aia_asn1 = ASN1.decode(ext.value_der)
            if ext.critical? || aia_asn1.tag_class != :UNIVERSAL || aia_asn1.tag != ASN1::SEQUENCE
              raise ASN1::ASN1Error, "invalid extension"
            end

            aia_asn1
          end
      end
    end

    class Name
      include OpenSSL::Marshal

      module RFC2253DN
        Special = ',=+<>#;'
        HexChar = /[0-9a-fA-F]/
        HexPair = /#{HexChar}#{HexChar}/
        HexString = /#{HexPair}+/
        Pair = /\\(?:[#{Special}]|\\|"|#{HexPair})/
        StringChar = /[^\\"#{Special}]/
        QuoteChar = /[^\\"]/
        AttributeType = /[a-zA-Z][0-9a-zA-Z]*|[0-9]+(?:\.[0-9]+)*/
        AttributeValue = /
          (?!["#])((?:#{StringChar}|#{Pair})*)|
          \#(#{HexString})|
          "((?:#{QuoteChar}|#{Pair})*)"
        /x
        TypeAndValue = /\A(#{AttributeType})=#{AttributeValue}/

        module_function

        def expand_pair(str)
          return nil unless str
          return str.gsub(Pair){
            pair = $&
            case pair.size
            when 2 then pair[1,1]
            when 3 then Integer("0x#{pair[1,2]}").chr
            else raise OpenSSL::X509::NameError, "invalid pair: #{str}"
            end
          }
        end

        def expand_hexstring(str)
          return nil unless str
          der = str.gsub(HexPair){$&.to_i(16).chr }
          a1 = OpenSSL::ASN1.decode(der)
          return a1.value, a1.tag
        end

        def expand_value(str1, str2, str3)
          value = expand_pair(str1)
          value, tag = expand_hexstring(str2) unless value
          value = expand_pair(str3) unless value
          return value, tag
        end

        def scan(dn)
          str = dn
          ary = []
          while true
            if md = TypeAndValue.match(str)
              remain = md.post_match
              type = md[1]
              value, tag = expand_value(md[2], md[3], md[4]) rescue nil
              if value
                type_and_value = [type, value]
                type_and_value.push(tag) if tag
                ary.unshift(type_and_value)
                if remain.length > 2 && remain[0] == ?,
                  str = remain[1..-1]
                  next
                elsif remain.length > 2 && remain[0] == ?+
                  raise OpenSSL::X509::NameError,
                    "multi-valued RDN is not supported: #{dn}"
                elsif remain.empty?
                  break
                end
              end
            end
            msg_dn = dn[0, dn.length - str.length] + " =>" + str
            raise OpenSSL::X509::NameError, "malformed RDN: #{msg_dn}"
          end
          return ary
        end
      end

      class << self
        # Parses the UTF-8 string representation of a distinguished name,
        # according to RFC 2253.
        #
        # See also #to_utf8 for the opposite operation.
        def parse_rfc2253(str, template=OBJECT_TYPE_TEMPLATE)
          ary = OpenSSL::X509::Name::RFC2253DN.scan(str)
          self.new(ary, template)
        end

        # Parses the string representation of a distinguished name. Two
        # different forms are supported:
        #
        # - \OpenSSL format (<tt>X509_NAME_oneline()</tt>) used by
        #   <tt>#to_s</tt>. For example: <tt>/DC=com/DC=example/CN=nobody</tt>
        # - \OpenSSL format (<tt>X509_NAME_print()</tt>)
        #   used by <tt>#to_s(OpenSSL::X509::Name::COMPAT)</tt>. For example:
        #   <tt>DC=com, DC=example, CN=nobody</tt>
        #
        # Neither of them is standardized and has quirks and inconsistencies
        # in handling of escaped characters or multi-valued RDNs.
        #
        # Use of this method is discouraged in new applications. See
        # Name.parse_rfc2253 and #to_utf8 for the alternative.
        def parse_openssl(str, template=OBJECT_TYPE_TEMPLATE)
          if str.start_with?("/")
            # /A=B/C=D format
            ary = str[1..-1].split("/").map { |i| i.split("=", 2) }
          else
            # Comma-separated
            ary = str.split(",").map { |i| i.strip.split("=", 2) }
          end
          self.new(ary, template)
        end

        alias parse parse_openssl
      end

      def pretty_print(q)
        q.object_group(self) {
          q.text ' '
          q.text to_s(OpenSSL::X509::Name::RFC2253)
        }
      end
    end

    class Attribute
      include OpenSSL::Marshal

      def ==(other)
        return false unless Attribute === other
        to_der == other.to_der
      end
    end

    class StoreContext
      def cleanup
        warn "(#{caller.first}) OpenSSL::X509::StoreContext#cleanup is deprecated with no replacement" if $VERBOSE
      end
    end

    class Certificate
      include OpenSSL::Marshal
      include Extension::SubjectKeyIdentifier
      include Extension::AuthorityKeyIdentifier
      include Extension::CRLDistributionPoints
      include Extension::AuthorityInfoAccess

      def pretty_print(q)
        q.object_group(self) {
          q.breakable
          q.text 'subject='; q.pp self.subject; q.text ','; q.breakable
          q.text 'issuer='; q.pp self.issuer; q.text ','; q.breakable
          q.text 'serial='; q.pp self.serial; q.text ','; q.breakable
          q.text 'not_before='; q.pp self.not_before; q.text ','; q.breakable
          q.text 'not_after='; q.pp self.not_after
        }
      end

      def self.load_file(path)
        load(File.binread(path))
      end
    end

    class CRL
      include OpenSSL::Marshal
      include Extension::AuthorityKeyIdentifier

      def ==(other)
        return false unless CRL === other
        to_der == other.to_der
      end
    end

    class Revoked
      def ==(other)
        return false unless Revoked === other
        to_der == other.to_der
      end
    end

    class Request
      include OpenSSL::Marshal

      def ==(other)
        return false unless Request === other
        to_der == other.to_der
      end
    end
  end
end
