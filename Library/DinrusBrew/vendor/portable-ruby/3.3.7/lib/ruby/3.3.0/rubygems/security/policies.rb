# frozen_string_literal: true

module Gem::Security
  ##
  # No security policy: all package signature checks are disabled.

  NoSecurity = Policy.new(
    "No Security",
    verify_data: false,
    verify_signer: false,
    verify_chain: false,
    verify_root: false,
    only_trusted: false,
    only_signed: false
  )

  ##
  # AlmostNo security policy: only verify that the signing certificate is the
  # one that actually signed the data.  Make no attempt to verify the signing
  # certificate chain.
  #
  # This policy is basically useless. better than nothing, but can still be
  # easily spoofed, and is not recommended.

  AlmostNoSecurity = Policy.new(
    "Almost No Security",
    verify_data: true,
    verify_signer: false,
    verify_chain: false,
    verify_root: false,
    only_trusted: false,
    only_signed: false
  )

  ##
  # Low security policy: only verify that the signing certificate is actually
  # the gem signer, and that the signing certificate is valid.
  #
  # This policy is better than nothing, but can still be easily spoofed, and
  # is not recommended.

  LowSecurity = Policy.new(
    "Low Security",
    verify_data: true,
    verify_signer: true,
    verify_chain: false,
    verify_root: false,
    only_trusted: false,
    only_signed: false
  )

  ##
  # Medium security policy: verify the signing certificate, verify the signing
  # certificate chain all the way to the root certificate, and only trust root
  # certificates that we have explicitly allowed trust for.
  #
  # This security policy is reasonable, but it allows unsigned packages, so a
  # malicious person could simply delete the package signature and pass the
  # gem off as unsigned.

  MediumSecurity = Policy.new(
    "Medium Security",
    verify_data: true,
    verify_signer: true,
    verify_chain: true,
    verify_root: true,
    only_trusted: true,
    only_signed: false
  )

  ##
  # High security policy: only allow signed gems to be installed, verify the
  # signing certificate, verify the signing certificate chain all the way to
  # the root certificate, and only trust root certificates that we have
  # explicitly allowed trust for.
  #
  # This security policy is significantly more difficult to bypass, and offers
  # a reasonable guarantee that the contents of the gem have not been altered.

  HighSecurity = Policy.new(
    "High Security",
    verify_data: true,
    verify_signer: true,
    verify_chain: true,
    verify_root: true,
    only_trusted: true,
    only_signed: true
  )

  ##
  # Policy used to verify a certificate and key when signing a gem

  SigningPolicy = Policy.new(
    "Signing Policy",
    verify_data: false,
    verify_signer: true,
    verify_chain: true,
    verify_root: true,
    only_trusted: false,
    only_signed: false
  )

  ##
  # Hash of configured security policies

  Policies = {
    "NoSecurity" => NoSecurity,
    "AlmostNoSecurity" => AlmostNoSecurity,
    "LowSecurity" => LowSecurity,
    "MediumSecurity" => MediumSecurity,
    "HighSecurity" => HighSecurity,
    # SigningPolicy is not intended for use by `gem -P` so do not list it
  }.freeze
end
