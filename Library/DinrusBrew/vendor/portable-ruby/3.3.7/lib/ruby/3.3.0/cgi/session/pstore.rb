# frozen_string_literal: true
#
# cgi/session/pstore.rb - persistent storage of marshalled session data
#
# Documentation: William Webber (william@williamwebber.com)
#
# == Overview
#
# This file provides the CGI::Session::PStore class, which builds
# persistent of session data on top of the pstore library.  See
# cgi/session.rb for more details on session storage managers.

require_relative '../session'
require 'pstore'

class CGI
  class Session
    # PStore-based session storage class.
    #
    # This builds upon the top-level PStore class provided by the
    # library file pstore.rb.  Session data is marshalled and stored
    # in a file.  File locking and transaction services are provided.
    class PStore
      # Create a new CGI::Session::PStore instance
      #
      # This constructor is used internally by CGI::Session.  The
      # user does not generally need to call it directly.
      #
      # +session+ is the session for which this instance is being
      # created.  The session id must only contain alphanumeric
      # characters; automatically generated session ids observe
      # this requirement.
      #
      # +option+ is a hash of options for the initializer.  The
      # following options are recognised:
      #
      # tmpdir:: the directory to use for storing the PStore
      #          file.  Defaults to Dir::tmpdir (generally "/tmp"
      #          on Unix systems).
      # prefix:: the prefix to add to the session id when generating
      #          the filename for this session's PStore file.
      #          Defaults to the empty string.
      #
      # This session's PStore file will be created if it does
      # not exist, or opened if it does.
      def initialize(session, option={})
        option = {'suffix'=>''}.update(option)
        path, @hash = session.new_store_file(option)
        @p = ::PStore.new(path)
        @p.transaction do |p|
          File.chmod(0600, p.path)
        end
      end

      # Restore session state from the session's PStore file.
      #
      # Returns the session state as a hash.
      def restore
        unless @hash
          @p.transaction do
            @hash = @p['hash'] || {}
          end
        end
        @hash
      end

      # Save session state to the session's PStore file.
      def update
        @p.transaction do
          @p['hash'] = @hash
        end
      end

      # Update and close the session's PStore file.
      def close
        update
      end

      # Close and delete the session's PStore file.
      def delete
        path = @p.path
        File::unlink path
      end

    end
  end
end
# :enddoc:
