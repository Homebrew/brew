# typed: strict
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
          bc-gh
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
          lldb
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

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?

          find_method_with_args(body_node, :keg_only, :provided_by_macos) do
            return if PROVIDED_BY_MACOS_FORMULAE.include? @formula_name

            problem "Formulae that are `keg_only :provided_by_macos` should be " \
                    "added to the `PROVIDED_BY_MACOS_FORMULAE` list (in the Homebrew/brew repository)"
          end
        end
      end

      # This cop audits `uses_from_macos` dependencies in formulae.
      class UsesFromMacos < FormulaCop
        extend AutoCorrector

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
          jq
          less
          mandoc
          openssl
          perl
          python
          rsync
          vim
          xz
          zsh
        ].freeze

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?

          depends_on_linux = depends_on_linux?(body_node)
          check_uses_from_macos_nodes(body_node, depends_on_linux)

          [:head, :stable].each do |spec|
            software_spec = find_block(body_node, spec)&.body
            next unless software_spec

            check_uses_from_macos_nodes(software_spec, depends_on_linux || depends_on_linux?(software_spec))
          end
        end

        sig { params(node: RuboCop::AST::Node, depends_on_linux: T::Boolean).void }
        def check_uses_from_macos_nodes(node, depends_on_linux)
          find_method_calls_by_name(node, :uses_from_macos).each do |method|
            offending_node(method)

            dep_arg = method.first_argument
            dep = case dep_arg
            when RuboCop::AST::StrNode
              dep_arg
            when RuboCop::AST::HashNode
              dep_arg = dep_arg.node_parts.first
              dep_arg.key if dep_arg.is_a?(RuboCop::AST::PairNode)
            end

            if depends_on_linux
              problem "`uses_from_macos` should not be used when Linux is required." do |corrector|
                corrector.replace(method.source_range, "depends_on #{dep_arg.source}") if dep
              end
              next
            end

            next if dep.nil?
            next unless dep.str_type?

            dep_name = string_content(dep)
            next if ALLOWED_USES_FROM_MACOS_DEPS.include? dep_name
            next if ProvidedByMacos::PROVIDED_BY_MACOS_FORMULAE.include? dep_name

            problem "`uses_from_macos` should only be used for macOS dependencies, not '#{dep_name}'." do |corrector|
              corrector.replace(method.source_range, "depends_on #{dep_arg.source}")
            end
          end
        end

        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def depends_on_linux?(node)
          find_method_calls_by_name(node, :depends_on).any? do |depends_on|
            depends_on_name_type?(depends_on, :linux, :any)
          end
        end
      end
    end
  end
end
