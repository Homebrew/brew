# frozen_string_literal: false
# Gem::URI is a module providing classes to handle Uniform Resource Identifiers
# (RFC2396[http://tools.ietf.org/html/rfc2396]).
#
# == Features
#
# * Uniform way of handling URIs.
# * Flexibility to introduce custom Gem::URI schemes.
# * Flexibility to have an alternate Gem::URI::Parser (or just different patterns
#   and regexp's).
#
# == Basic example
#
#   require 'rubygems/vendor/uri/lib/uri'
#
#   uri = Gem::URI("http://foo.com/posts?id=30&limit=5#time=1305298413")
#   #=> #<Gem::URI::HTTP http://foo.com/posts?id=30&limit=5#time=1305298413>
#
#   uri.scheme    #=> "http"
#   uri.host      #=> "foo.com"
#   uri.path      #=> "/posts"
#   uri.query     #=> "id=30&limit=5"
#   uri.fragment  #=> "time=1305298413"
#
#   uri.to_s      #=> "http://foo.com/posts?id=30&limit=5#time=1305298413"
#
# == Adding custom URIs
#
#   module Gem::URI
#     class RSYNC < Generic
#       DEFAULT_PORT = 873
#     end
#     register_scheme 'RSYNC', RSYNC
#   end
#   #=> Gem::URI::RSYNC
#
#   Gem::URI.scheme_list
#   #=> {"FILE"=>Gem::URI::File, "FTP"=>Gem::URI::FTP, "HTTP"=>Gem::URI::HTTP,
#   #    "HTTPS"=>Gem::URI::HTTPS, "LDAP"=>Gem::URI::LDAP, "LDAPS"=>Gem::URI::LDAPS,
#   #    "MAILTO"=>Gem::URI::MailTo, "RSYNC"=>Gem::URI::RSYNC}
#
#   uri = Gem::URI("rsync://rsync.foo.com")
#   #=> #<Gem::URI::RSYNC rsync://rsync.foo.com>
#
# == RFC References
#
# A good place to view an RFC spec is http://www.ietf.org/rfc.html.
#
# Here is a list of all related RFC's:
# - RFC822[http://tools.ietf.org/html/rfc822]
# - RFC1738[http://tools.ietf.org/html/rfc1738]
# - RFC2255[http://tools.ietf.org/html/rfc2255]
# - RFC2368[http://tools.ietf.org/html/rfc2368]
# - RFC2373[http://tools.ietf.org/html/rfc2373]
# - RFC2396[http://tools.ietf.org/html/rfc2396]
# - RFC2732[http://tools.ietf.org/html/rfc2732]
# - RFC3986[http://tools.ietf.org/html/rfc3986]
#
# == Class tree
#
# - Gem::URI::Generic (in uri/generic.rb)
#   - Gem::URI::File - (in uri/file.rb)
#   - Gem::URI::FTP - (in uri/ftp.rb)
#   - Gem::URI::HTTP - (in uri/http.rb)
#     - Gem::URI::HTTPS - (in uri/https.rb)
#   - Gem::URI::LDAP - (in uri/ldap.rb)
#     - Gem::URI::LDAPS - (in uri/ldaps.rb)
#   - Gem::URI::MailTo - (in uri/mailto.rb)
# - Gem::URI::Parser - (in uri/common.rb)
# - Gem::URI::REGEXP - (in uri/common.rb)
#   - Gem::URI::REGEXP::PATTERN - (in uri/common.rb)
# - Gem::URI::Util - (in uri/common.rb)
# - Gem::URI::Error - (in uri/common.rb)
#   - Gem::URI::InvalidURIError - (in uri/common.rb)
#   - Gem::URI::InvalidComponentError - (in uri/common.rb)
#   - Gem::URI::BadURIError - (in uri/common.rb)
#
# == Copyright Info
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# Documentation::
#   Akira Yamada <akira@ruby-lang.org>
#   Dmitry V. Sabanin <sdmitry@lrn.ru>
#   Vincent Batts <vbatts@hashbangbash.com>
# License::
#  Copyright (c) 2001 akira yamada <akira@ruby-lang.org>
#  You can redistribute it and/or modify it under the same term as Ruby.
#

module Gem::URI
end

require_relative 'uri/version'
require_relative 'uri/common'
require_relative 'uri/generic'
require_relative 'uri/file'
require_relative 'uri/ftp'
require_relative 'uri/http'
require_relative 'uri/https'
require_relative 'uri/ldap'
require_relative 'uri/ldaps'
require_relative 'uri/mailto'
require_relative 'uri/ws'
require_relative 'uri/wss'
