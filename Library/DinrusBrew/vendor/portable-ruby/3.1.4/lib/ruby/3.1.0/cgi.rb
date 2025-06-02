# frozen_string_literal: true
#
# cgi.rb - cgi support library
#
# Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
#
# Copyright (C) 2000  Information-technology Promotion Agency, Japan
#
# Author: Wakou Aoyama <wakou@ruby-lang.org>
#
# Documentation: Wakou Aoyama (RDoc'd and embellished by William Webber)
#

# == Overview
#
# The Common Gateway Interface (CGI) is a simple protocol for passing an HTTP
# request from a web server to a standalone program, and returning the output
# to the web browser.  Basically, a CGI program is called with the parameters
# of the request passed in either in the environment (GET) or via $stdin
# (POST), and everything it prints to $stdout is returned to the client.
#
# This file holds the CGI class.  This class provides functionality for
# retrieving HTTP request parameters, managing cookies, and generating HTML
# output.
#
# The file CGI::Session provides session management functionality; see that
# class for more details.
#
# See http://www.w3.org/CGI/ for more information on the CGI protocol.
#
# == Introduction
#
# CGI is a large class, providing several categories of methods, many of which
# are mixed in from other modules.  Some of the documentation is in this class,
# some in the modules CGI::QueryExtension and CGI::HtmlExtension.  See
# CGI::Cookie for specific information on handling cookies, and cgi/session.rb
# (CGI::Session) for information on sessions.
#
# For queries, CGI provides methods to get at environmental variables,
# parameters, cookies, and multipart request data.  For responses, CGI provides
# methods for writing output and generating HTML.
#
# Read on for more details.  Examples are provided at the bottom.
#
# == Queries
#
# The CGI class dynamically mixes in parameter and cookie-parsing
# functionality,  environmental variable access, and support for
# parsing multipart requests (including uploaded files) from the
# CGI::QueryExtension module.
#
# === Environmental Variables
#
# The standard CGI environmental variables are available as read-only
# attributes of a CGI object.  The following is a list of these variables:
#
#
#   AUTH_TYPE               HTTP_HOST          REMOTE_IDENT
#   CONTENT_LENGTH          HTTP_NEGOTIATE     REMOTE_USER
#   CONTENT_TYPE            HTTP_PRAGMA        REQUEST_METHOD
#   GATEWAY_INTERFACE       HTTP_REFERER       SCRIPT_NAME
#   HTTP_ACCEPT             HTTP_USER_AGENT    SERVER_NAME
#   HTTP_ACCEPT_CHARSET     PATH_INFO          SERVER_PORT
#   HTTP_ACCEPT_ENCODING    PATH_TRANSLATED    SERVER_PROTOCOL
#   HTTP_ACCEPT_LANGUAGE    QUERY_STRING       SERVER_SOFTWARE
#   HTTP_CACHE_CONTROL      REMOTE_ADDR
#   HTTP_FROM               REMOTE_HOST
#
#
# For each of these variables, there is a corresponding attribute with the
# same name, except all lower case and without a preceding HTTP_.
# +content_length+ and +server_port+ are integers; the rest are strings.
#
# === Parameters
#
# The method #params() returns a hash of all parameters in the request as
# name/value-list pairs, where the value-list is an Array of one or more
# values.  The CGI object itself also behaves as a hash of parameter names
# to values, but only returns a single value (as a String) for each
# parameter name.
#
# For instance, suppose the request contains the parameter
# "favourite_colours" with the multiple values "blue" and "green".  The
# following behavior would occur:
#
#   cgi.params["favourite_colours"]  # => ["blue", "green"]
#   cgi["favourite_colours"]         # => "blue"
#
# If a parameter does not exist, the former method will return an empty
# array, the latter an empty string.  The simplest way to test for existence
# of a parameter is by the #has_key? method.
#
# === Cookies
#
# HTTP Cookies are automatically parsed from the request.  They are available
# from the #cookies() accessor, which returns a hash from cookie name to
# CGI::Cookie object.
#
# === Multipart requests
#
# If a request's method is POST and its content type is multipart/form-data,
# then it may contain uploaded files.  These are stored by the QueryExtension
# module in the parameters of the request.  The parameter name is the name
# attribute of the file input field, as usual.  However, the value is not
# a string, but an IO object, either an IOString for small files, or a
# Tempfile for larger ones.  This object also has the additional singleton
# methods:
#
# #local_path():: the path of the uploaded file on the local filesystem
# #original_filename():: the name of the file on the client computer
# #content_type():: the content type of the file
#
# == Responses
#
# The CGI class provides methods for sending header and content output to
# the HTTP client, and mixes in methods for programmatic HTML generation
# from CGI::HtmlExtension and CGI::TagMaker modules.  The precise version of HTML
# to use for HTML generation is specified at object creation time.
#
# === Writing output
#
# The simplest way to send output to the HTTP client is using the #out() method.
# This takes the HTTP headers as a hash parameter, and the body content
# via a block.  The headers can be generated as a string using the #http_header()
# method.  The output stream can be written directly to using the #print()
# method.
#
# === Generating HTML
#
# Each HTML element has a corresponding method for generating that
# element as a String.  The name of this method is the same as that
# of the element, all lowercase.  The attributes of the element are
# passed in as a hash, and the body as a no-argument block that evaluates
# to a String.  The HTML generation module knows which elements are
# always empty, and silently drops any passed-in body.  It also knows
# which elements require matching closing tags and which don't.  However,
# it does not know what attributes are legal for which elements.
#
# There are also some additional HTML generation methods mixed in from
# the CGI::HtmlExtension module.  These include individual methods for the
# different types of form inputs, and methods for elements that commonly
# take particular attributes where the attributes can be directly specified
# as arguments, rather than via a hash.
#
# === Utility HTML escape and other methods like a function.
#
# There are some utility tool defined in cgi/util.rb .
# And when include, you can use utility methods like a function.
#
# == Examples of use
#
# === Get form values
#
#   require "cgi"
#   cgi = CGI.new
#   value = cgi['field_name']   # <== value string for 'field_name'
#     # if not 'field_name' included, then return "".
#   fields = cgi.keys            # <== array of field names
#
#   # returns true if form has 'field_name'
#   cgi.has_key?('field_name')
#   cgi.has_key?('field_name')
#   cgi.include?('field_name')
#
# CAUTION! <code>cgi['field_name']</code> returned an Array with the old
# cgi.rb(included in Ruby 1.6)
#
# === Get form values as hash
#
#   require "cgi"
#   cgi = CGI.new
#   params = cgi.params
#
# cgi.params is a hash.
#
#   cgi.params['new_field_name'] = ["value"]  # add new param
#   cgi.params['field_name'] = ["new_value"]  # change value
#   cgi.params.delete('field_name')           # delete param
#   cgi.params.clear                          # delete all params
#
#
# === Save form values to file
#
#   require "pstore"
#   db = PStore.new("query.db")
#   db.transaction do
#     db["params"] = cgi.params
#   end
#
#
# === Restore form values from file
#
#   require "pstore"
#   db = PStore.new("query.db")
#   db.transaction do
#     cgi.params = db["params"]
#   end
#
#
# === Get multipart form values
#
#   require "cgi"
#   cgi = CGI.new
#   value = cgi['field_name']   # <== value string for 'field_name'
#   value.read                  # <== body of value
#   value.local_path            # <== path to local file of value
#   value.original_filename     # <== original filename of value
#   value.content_type          # <== content_type of value
#
# and value has StringIO or Tempfile class methods.
#
# === Get cookie values
#
#   require "cgi"
#   cgi = CGI.new
#   values = cgi.cookies['name']  # <== array of 'name'
#     # if not 'name' included, then return [].
#   names = cgi.cookies.keys      # <== array of cookie names
#
# and cgi.cookies is a hash.
#
# === Get cookie objects
#
#   require "cgi"
#   cgi = CGI.new
#   for name, cookie in cgi.cookies
#     cookie.expires = Time.now + 30
#   end
#   cgi.out("cookie" => cgi.cookies) {"string"}
#
#   cgi.cookies # { "name1" => cookie1, "name2" => cookie2, ... }
#
#   require "cgi"
#   cgi = CGI.new
#   cgi.cookies['name'].expires = Time.now + 30
#   cgi.out("cookie" => cgi.cookies['name']) {"string"}
#
# === Print http header and html string to $DEFAULT_OUTPUT ($>)
#
#   require "cgi"
#   cgi = CGI.new("html4")  # add HTML generation methods
#   cgi.out do
#     cgi.html do
#       cgi.head do
#         cgi.title { "TITLE" }
#       end +
#       cgi.body do
#         cgi.form("ACTION" => "uri") do
#           cgi.p do
#             cgi.textarea("get_text") +
#             cgi.br +
#             cgi.submit
#           end
#         end +
#         cgi.pre do
#           CGI.escapeHTML(
#             "params: #{cgi.params.inspect}\n" +
#             "cookies: #{cgi.cookies.inspect}\n" +
#             ENV.collect do |key, value|
#               "#{key} --> #{value}\n"
#             end.join("")
#           )
#         end
#       end
#     end
#   end
#
#   # add HTML generation methods
#   CGI.new("html3")    # html3.2
#   CGI.new("html4")    # html4.01 (Strict)
#   CGI.new("html4Tr")  # html4.01 Transitional
#   CGI.new("html4Fr")  # html4.01 Frameset
#   CGI.new("html5")    # html5
#
# === Some utility methods
#
#   require 'cgi/util'
#   CGI.escapeHTML('Usage: foo "bar" <baz>')
#
#
# === Some utility methods like a function
#
#   require 'cgi/util'
#   include CGI::Util
#   escapeHTML('Usage: foo "bar" <baz>')
#   h('Usage: foo "bar" <baz>') # alias
#
#

class CGI
  VERSION = "0.3.6"
end

require 'cgi/core'
require 'cgi/cookie'
require 'cgi/util'
CGI.autoload(:HtmlExtension, 'cgi/html')
