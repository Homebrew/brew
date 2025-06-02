# frozen_string_literal: true
=begin

= net/https -- SSL/TLS enhancement for Gem::Net::HTTP.

  This file has been merged with net/http.  There is no longer any need to
  require_relative 'https' to use HTTPS.

  See Gem::Net::HTTP for details on how to make HTTPS connections.

== Info
  'OpenSSL for Ruby 2' project
  Copyright (C) 2001 GOTOU Yuuzou <gotoyuzo@notwork.org>
  All rights reserved.

== Licence
  This program is licensed under the same licence as Ruby.
  (See the file 'LICENCE'.)

=end

require_relative 'http'
require 'openssl'
