# typed: strict
# frozen_string_literal: true

require "cask/audit"

module Cask
  # Helper class for auditing all available languages of a cask.
  class Auditor
    # TODO: use argument forwarding (...) when Sorbet supports it in strict mode
    sig {
      params(
        cask: ::Cask::Cask, audit_download: T::Boolean, audit_online: T.nilable(T::Boolean),
        audit_strict: T.nilable(T::Boolean), audit_signing: T.nilable(T::Boolean),
        audit_token_conflicts: T.nilable(T::Boolean), audit_new_cask: T.nilable(T::Boolean), quarantine: T::Boolean,
        any_named_args: T::Boolean, language: T.nilable(String), only: T::Array[String], except: T::Array[String]
      ).returns(T::Set[String])
    }
    def self.audit(
      cask, audit_download: false, audit_online: nil, audit_strict: nil, audit_signing: nil,
      audit_token_conflicts: nil, audit_new_cask: nil, quarantine: false, any_named_args: false, language: nil,
      only: [], except: []
    )
      new(
        cask, audit_download:, audit_online:, audit_strict:, audit_signing:, audit_token_conflicts:,
        audit_new_cask:, quarantine:, any_named_args:, language:, only:, except:
      ).audit
    end

    sig { returns(::Cask::Cask) }
    attr_reader :cask

    sig { returns(T.nilable(String)) }
    attr_reader :language

    sig {
      params(
        cask: ::Cask::Cask, audit_download: T::Boolean, audit_online: T.nilable(T::Boolean),
        audit_strict: T.nilable(T::Boolean), audit_signing: T.nilable(T::Boolean),
        audit_token_conflicts: T.nilable(T::Boolean), audit_new_cask: T.nilable(T::Boolean), quarantine: T::Boolean,
        any_named_args: T::Boolean, language: T.nilable(String), only: T::Array[String], except: T::Array[String]
      ).void
    }
    def initialize(
      cask,
      audit_download: false,
      audit_online: nil,
      audit_strict: nil,
      audit_signing: nil,
      audit_token_conflicts: nil,
      audit_new_cask: nil,
      quarantine: false,
      any_named_args: false,
      language: nil,
      only: [],
      except: []
    )
      @cask = cask
      @audit_download = audit_download
      @audit_online = audit_online
      @audit_new_cask = audit_new_cask
      @audit_strict = audit_strict
      @audit_signing = audit_signing
      @quarantine = quarantine
      @audit_token_conflicts = audit_token_conflicts
      @any_named_args = any_named_args
      @language = language
      @only = only
      @except = except
    end

    LANGUAGE_BLOCK_LIMIT = 10

    sig { returns(T::Set[String]) }
    def audit
      errors = Set.new

      if !language && (blocks = language_blocks)
        sample_languages = if blocks.length > LANGUAGE_BLOCK_LIMIT && !@audit_new_cask
          sample_keys = T.must(blocks.keys.sample(LANGUAGE_BLOCK_LIMIT))
          ohai "Auditing a sample of available languages for #{cask}: " \
               "#{sample_keys.map { |lang| lang[0].to_s }.to_sentence}"
          blocks.select { |k| sample_keys.include?(k) }
        else
          blocks
        end

        sample_languages.each_key do |l|
          audit = audit_languages(l)
          if audit.summary.present? && output_summary?(audit)
            ohai "Auditing language: #{l.map { |lang| "'#{lang}'" }.to_sentence}" if output_summary?
            puts audit.summary
          end
          errors += audit.errors
        end
      else
        audit = audit_cask_instance(cask)
        puts audit.summary if audit.summary.present? && output_summary?(audit)
        errors += audit.errors
      end

      errors
    end

    private

    sig { params(audit: T.nilable(Audit)).returns(T::Boolean) }
    def output_summary?(audit = nil)
      return true if @any_named_args
      return true if @audit_strict
      return false if audit.nil?

      audit.errors?
    end

    sig { params(languages: T::Array[String]).returns(::Cask::Audit) }
    def audit_languages(languages)
      original_config = cask.config
      localized_config = original_config.merge(Config.new(explicit: { languages: }))
      cask.config = localized_config

      audit_cask_instance(cask)
    ensure
      cask.config = original_config
    end

    sig { params(cask: ::Cask::Cask).returns(::Cask::Audit) }
    def audit_cask_instance(cask)
      audit = Audit.new(
        cask,
        online:          @audit_online,
        strict:          @audit_strict,
        signing:         @audit_signing,
        new_cask:        @audit_new_cask,
        token_conflicts: @audit_token_conflicts,
        download:        @audit_download,
        quarantine:      @quarantine,
        only:            @only,
        except:          @except,
      )
      audit.run!
    end

    sig { returns(T.nilable(T::Hash[T::Array[String], T.proc.returns(T.untyped)])) }
    def language_blocks
      cask.instance_variable_get(:@dsl).instance_variable_get(:@language_blocks)
    end
  end
end
