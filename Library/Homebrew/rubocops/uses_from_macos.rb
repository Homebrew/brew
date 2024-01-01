# typed: true
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop audits formulae that are keg-only because they are provided by macos.
      class ProvidedByMacos < FormulaCop
        PROVIDED_BY_MACOS_FORMULAE = %w[
          apr
          bc
          berkeley-db
          bison
          bzip2
          cups
          curl
          cyrus-sasl
          dyld-headers
          ed
          expat
          file-formula
          flex
          gnu-getopt
          gperf
          icu4c
          krb5
          libarchive
          libedit
          libffi
          libiconv
          libpcap
          libressl
          libxcrypt
          libxml2
          libxslt
          llvm
          lsof
          m4
          ncompress
          ncurses
          net-snmp
          netcat
          openldap
          pax
          pcsc-lite
          pod2man
          rpcgen
          ruby
          sqlite
          ssh-copy-id
          swift
          tcl-tk
          unifdef
          unzip
          whois
          zip
          zlib
        ].freeze

        def audit_formula(_node, _class_node, _parent_class_node, body_node)
          return if body_node.nil?

          find_method_with_args(body_node, :keg_only, :provided_by_macos) do
            return if PROVIDED_BY_MACOS_FORMULAE.include? @formula_name

            problem "Formulae that are `keg_only :provided_by_macos` should be " \
                    "added to the `PROVIDED_BY_MACOS_FORMULAE` list (in the Homebrew/brew repo)"
          end
        end
      end

      # This cop audits `uses_from_macos` dependencies in formulae.
      class UsesFromMacos < FormulaCop
        # These formulae aren't `keg_only :provided_by_macos` but are provided by
        # macOS (or very similarly, e.g. OpenSSL where system provides LibreSSL).
        # TODO: consider making some of these keg-only.
        ALLOWED_USES_FROM_MACOS_DEPS = %w[
          bash
          cpio
          expect
          git
          groff
          gzip
          less
          mandoc
          openssl
          perl
          php
          python
          rsync
          vim
          xz
          zsh
        ].freeze

        def audit_formula(_node, _class_node, _parent_class_node, body_node)
          return if body_node.nil?

          depends_on_linux = depends_on?(:linux)

          find_method_with_args(body_node, :uses_from_macos, /^"(.+)"/).each do |method|
            @offensive_node = method
            problem "`uses_from_macos` should not be used when Linux is required." if depends_on_linux

            dep = if parameters(method).first.instance_of?(RuboCop::AST::StrNode)
              parameters(method).first
            elsif parameters(method).first.instance_of?(RuboCop::AST::HashNode)
              parameters(method).first.keys.first
            end

            dep_name = string_content(dep)
            next if ALLOWED_USES_FROM_MACOS_DEPS.include? dep_name
            next if ProvidedByMacos::PROVIDED_BY_MACOS_FORMULAE.include? dep_name

            problem "`uses_from_macos` should only be used for macOS dependencies, not #{dep_name}."
          end
        end
      end
    end
  end
end
