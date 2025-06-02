# frozen_string_literal: true
#
# = net/http.rb
#
# Copyright (c) 1999-2007 Yukihiro Matsumoto
# Copyright (c) 1999-2007 Minero Aoki
# Copyright (c) 2001 GOTOU Yuuzou
#
# Written and maintained by Minero Aoki <aamine@loveruby.net>.
# HTTPS support added by GOTOU Yuuzou <gotoyuzo@notwork.org>.
#
# This file is derived from "http-access.rb".
#
# Documented by Minero Aoki; converted to RDoc by William Webber.
#
# This program is free software. You can re-distribute and/or
# modify this program under the same terms of ruby itself ---
# Ruby Distribution License or GNU General Public License.
#
# See Gem::Net::HTTP for an overview and examples.
#

require_relative '../../../net-protocol/lib/net/protocol'
require_relative '../../../uri/lib/uri'
require_relative '../../../resolv/lib/resolv'
autoload :OpenSSL, 'openssl'

module Gem::Net   #:nodoc:

  # :stopdoc:
  class HTTPBadResponse < StandardError; end
  class HTTPHeaderSyntaxError < StandardError; end
  # :startdoc:

  # \Class \Gem::Net::HTTP provides a rich library that implements the client
  # in a client-server model that uses the \HTTP request-response protocol.
  # For information about \HTTP, see:
  #
  # - {Hypertext Transfer Protocol}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol].
  # - {Technical overview}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Technical_overview].
  #
  # == About the Examples
  #
  # :include: doc/net-http/examples.rdoc
  #
  # == Strategies
  #
  # - If you will make only a few GET requests,
  #   consider using {OpenURI}[rdoc-ref:OpenURI].
  # - If you will make only a few requests of all kinds,
  #   consider using the various singleton convenience methods in this class.
  #   Each of the following methods automatically starts and finishes
  #   a {session}[rdoc-ref:Gem::Net::HTTP@Sessions] that sends a single request:
  #
  #     # Return string response body.
  #     Gem::Net::HTTP.get(hostname, path)
  #     Gem::Net::HTTP.get(uri)
  #
  #     # Write string response body to $stdout.
  #     Gem::Net::HTTP.get_print(hostname, path)
  #     Gem::Net::HTTP.get_print(uri)
  #
  #     # Return response as Gem::Net::HTTPResponse object.
  #     Gem::Net::HTTP.get_response(hostname, path)
  #     Gem::Net::HTTP.get_response(uri)
  #     data = '{"title": "foo", "body": "bar", "userId": 1}'
  #     Gem::Net::HTTP.post(uri, data)
  #     params = {title: 'foo', body: 'bar', userId: 1}
  #     Gem::Net::HTTP.post_form(uri, params)
  #
  # - If performance is important, consider using sessions, which lower request overhead.
  #   This {session}[rdoc-ref:Gem::Net::HTTP@Sessions] has multiple requests for
  #   {HTTP methods}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Request_methods]
  #   and {WebDAV methods}[https://en.wikipedia.org/wiki/WebDAV#Implementation]:
  #
  #     Gem::Net::HTTP.start(hostname) do |http|
  #       # Session started automatically before block execution.
  #       http.get(path)
  #       http.head(path)
  #       body = 'Some text'
  #       http.post(path, body)  # Can also have a block.
  #       http.put(path, body)
  #       http.delete(path)
  #       http.options(path)
  #       http.trace(path)
  #       http.patch(path, body) # Can also have a block.
  #       http.copy(path)
  #       http.lock(path, body)
  #       http.mkcol(path, body)
  #       http.move(path)
  #       http.propfind(path, body)
  #       http.proppatch(path, body)
  #       http.unlock(path, body)
  #       # Session finished automatically at block exit.
  #     end
  #
  # The methods cited above are convenience methods that, via their few arguments,
  # allow minimal control over the requests.
  # For greater control, consider using {request objects}[rdoc-ref:Gem::Net::HTTPRequest].
  #
  # == URIs
  #
  # On the internet, a URI
  # ({Universal Resource Identifier}[https://en.wikipedia.org/wiki/Uniform_Resource_Identifier])
  # is a string that identifies a particular resource.
  # It consists of some or all of: scheme, hostname, path, query, and fragment;
  # see {URI syntax}[https://en.wikipedia.org/wiki/Uniform_Resource_Identifier#Syntax].
  #
  # A Ruby {Gem::URI::Generic}[rdoc-ref:Gem::URI::Generic] object
  # represents an internet URI.
  # It provides, among others, methods
  # +scheme+, +hostname+, +path+, +query+, and +fragment+.
  #
  # === Schemes
  #
  # An internet \Gem::URI has
  # a {scheme}[https://en.wikipedia.org/wiki/List_of_URI_schemes].
  #
  # The two schemes supported in \Gem::Net::HTTP are <tt>'https'</tt> and <tt>'http'</tt>:
  #
  #   uri.scheme                       # => "https"
  #   Gem::URI('http://example.com').scheme # => "http"
  #
  # === Hostnames
  #
  # A hostname identifies a server (host) to which requests may be sent:
  #
  #   hostname = uri.hostname # => "jsonplaceholder.typicode.com"
  #   Gem::Net::HTTP.start(hostname) do |http|
  #     # Some HTTP stuff.
  #   end
  #
  # === Paths
  #
  # A host-specific path identifies a resource on the host:
  #
  #   _uri = uri.dup
  #   _uri.path = '/todos/1'
  #   hostname = _uri.hostname
  #   path = _uri.path
  #   Gem::Net::HTTP.get(hostname, path)
  #
  # === Queries
  #
  # A host-specific query adds name/value pairs to the URI:
  #
  #   _uri = uri.dup
  #   params = {userId: 1, completed: false}
  #   _uri.query = Gem::URI.encode_www_form(params)
  #   _uri # => #<Gem::URI::HTTPS https://jsonplaceholder.typicode.com?userId=1&completed=false>
  #   Gem::Net::HTTP.get(_uri)
  #
  # === Fragments
  #
  # A {URI fragment}[https://en.wikipedia.org/wiki/URI_fragment] has no effect
  # in \Gem::Net::HTTP;
  # the same data is returned, regardless of whether a fragment is included.
  #
  # == Request Headers
  #
  # Request headers may be used to pass additional information to the host,
  # similar to arguments passed in a method call;
  # each header is a name/value pair.
  #
  # Each of the \Gem::Net::HTTP methods that sends a request to the host
  # has optional argument +headers+,
  # where the headers are expressed as a hash of field-name/value pairs:
  #
  #   headers = {Accept: 'application/json', Connection: 'Keep-Alive'}
  #   Gem::Net::HTTP.get(uri, headers)
  #
  # See lists of both standard request fields and common request fields at
  # {Request Fields}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#Request_fields].
  # A host may also accept other custom fields.
  #
  # == \HTTP Sessions
  #
  # A _session_ is a connection between a server (host) and a client that:
  #
  # - Is begun by instance method Gem::Net::HTTP#start.
  # - May contain any number of requests.
  # - Is ended by instance method Gem::Net::HTTP#finish.
  #
  # See example sessions at {Strategies}[rdoc-ref:Gem::Net::HTTP@Strategies].
  #
  # === Session Using \Gem::Net::HTTP.start
  #
  # If you have many requests to make to a single host (and port),
  # consider using singleton method Gem::Net::HTTP.start with a block;
  # the method handles the session automatically by:
  #
  # - Calling #start before block execution.
  # - Executing the block.
  # - Calling #finish after block execution.
  #
  # In the block, you can use these instance methods,
  # each of which that sends a single request:
  #
  # - {HTTP methods}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Request_methods]:
  #
  #   - #get, #request_get: GET.
  #   - #head, #request_head: HEAD.
  #   - #post, #request_post: POST.
  #   - #delete: DELETE.
  #   - #options: OPTIONS.
  #   - #trace: TRACE.
  #   - #patch: PATCH.
  #
  # - {WebDAV methods}[https://en.wikipedia.org/wiki/WebDAV#Implementation]:
  #
  #   - #copy: COPY.
  #   - #lock: LOCK.
  #   - #mkcol: MKCOL.
  #   - #move: MOVE.
  #   - #propfind: PROPFIND.
  #   - #proppatch: PROPPATCH.
  #   - #unlock: UNLOCK.
  #
  # === Session Using \Gem::Net::HTTP.start and \Gem::Net::HTTP.finish
  #
  # You can manage a session manually using methods #start and #finish:
  #
  #   http = Gem::Net::HTTP.new(hostname)
  #   http.start
  #   http.get('/todos/1')
  #   http.get('/todos/2')
  #   http.delete('/posts/1')
  #   http.finish # Needed to free resources.
  #
  # === Single-Request Session
  #
  # Certain convenience methods automatically handle a session by:
  #
  # - Creating an \HTTP object
  # - Starting a session.
  # - Sending a single request.
  # - Finishing the session.
  # - Destroying the object.
  #
  # Such methods that send GET requests:
  #
  # - ::get: Returns the string response body.
  # - ::get_print: Writes the string response body to $stdout.
  # - ::get_response: Returns a Gem::Net::HTTPResponse object.
  #
  # Such methods that send POST requests:
  #
  # - ::post: Posts data to the host.
  # - ::post_form: Posts form data to the host.
  #
  # == \HTTP Requests and Responses
  #
  # Many of the methods above are convenience methods,
  # each of which sends a request and returns a string
  # without directly using \Gem::Net::HTTPRequest and \Gem::Net::HTTPResponse objects.
  #
  # You can, however, directly create a request object, send the request,
  # and retrieve the response object; see:
  #
  # - Gem::Net::HTTPRequest.
  # - Gem::Net::HTTPResponse.
  #
  # == Following Redirection
  #
  # Each returned response is an instance of a subclass of Gem::Net::HTTPResponse.
  # See the {response class hierarchy}[rdoc-ref:Gem::Net::HTTPResponse@Response+Subclasses].
  #
  # In particular, class Gem::Net::HTTPRedirection is the parent
  # of all redirection classes.
  # This allows you to craft a case statement to handle redirections properly:
  #
  #   def fetch(uri, limit = 10)
  #     # You should choose a better exception.
  #     raise ArgumentError, 'Too many HTTP redirects' if limit == 0
  #
  #     res = Gem::Net::HTTP.get_response(Gem::URI(uri))
  #     case res
  #     when Gem::Net::HTTPSuccess     # Any success class.
  #       res
  #     when Gem::Net::HTTPRedirection # Any redirection class.
  #       location = res['Location']
  #       warn "Redirected to #{location}"
  #       fetch(location, limit - 1)
  #     else                      # Any other class.
  #       res.value
  #     end
  #   end
  #
  #   fetch(uri)
  #
  # == Basic Authentication
  #
  # Basic authentication is performed according to
  # {RFC2617}[http://www.ietf.org/rfc/rfc2617.txt]:
  #
  #   req = Gem::Net::HTTP::Get.new(uri)
  #   req.basic_auth('user', 'pass')
  #   res = Gem::Net::HTTP.start(hostname) do |http|
  #     http.request(req)
  #   end
  #
  # == Streaming Response Bodies
  #
  # By default \Gem::Net::HTTP reads an entire response into memory.  If you are
  # handling large files or wish to implement a progress bar you can instead
  # stream the body directly to an IO.
  #
  #   Gem::Net::HTTP.start(hostname) do |http|
  #     req = Gem::Net::HTTP::Get.new(uri)
  #     http.request(req) do |res|
  #       open('t.tmp', 'w') do |f|
  #         res.read_body do |chunk|
  #           f.write chunk
  #         end
  #       end
  #     end
  #   end
  #
  # == HTTPS
  #
  # HTTPS is enabled for an \HTTP connection by Gem::Net::HTTP#use_ssl=:
  #
  #   Gem::Net::HTTP.start(hostname, :use_ssl => true) do |http|
  #     req = Gem::Net::HTTP::Get.new(uri)
  #     res = http.request(req)
  #   end
  #
  # Or if you simply want to make a GET request, you may pass in a URI
  # object that has an \HTTPS URL. \Gem::Net::HTTP automatically turns on TLS
  # verification if the URI object has a 'https' :URI scheme:
  #
  #   uri # => #<Gem::URI::HTTPS https://jsonplaceholder.typicode.com/>
  #   Gem::Net::HTTP.get(uri)
  #
  # == Proxy Server
  #
  # An \HTTP object can have
  # a {proxy server}[https://en.wikipedia.org/wiki/Proxy_server].
  #
  # You can create an \HTTP object with a proxy server
  # using method Gem::Net::HTTP.new or method Gem::Net::HTTP.start.
  #
  # The proxy may be defined either by argument +p_addr+
  # or by environment variable <tt>'http_proxy'</tt>.
  #
  # === Proxy Using Argument +p_addr+ as a \String
  #
  # When argument +p_addr+ is a string hostname,
  # the returned +http+ has the given host as its proxy:
  #
  #   http = Gem::Net::HTTP.new(hostname, nil, 'proxy.example')
  #   http.proxy?          # => true
  #   http.proxy_from_env? # => false
  #   http.proxy_address   # => "proxy.example"
  #   # These use default values.
  #   http.proxy_port      # => 80
  #   http.proxy_user      # => nil
  #   http.proxy_pass      # => nil
  #
  # The port, username, and password for the proxy may also be given:
  #
  #   http = Gem::Net::HTTP.new(hostname, nil, 'proxy.example', 8000, 'pname', 'ppass')
  #   # => #<Gem::Net::HTTP jsonplaceholder.typicode.com:80 open=false>
  #   http.proxy?          # => true
  #   http.proxy_from_env? # => false
  #   http.proxy_address   # => "proxy.example"
  #   http.proxy_port      # => 8000
  #   http.proxy_user      # => "pname"
  #   http.proxy_pass      # => "ppass"
  #
  # === Proxy Using '<tt>ENV['http_proxy']</tt>'
  #
  # When environment variable <tt>'http_proxy'</tt>
  # is set to a \Gem::URI string,
  # the returned +http+ will have the server at that URI as its proxy;
  # note that the \Gem::URI string must have a protocol
  # such as <tt>'http'</tt> or <tt>'https'</tt>:
  #
  #   ENV['http_proxy'] = 'http://example.com'
  #   http = Gem::Net::HTTP.new(hostname)
  #   http.proxy?          # => true
  #   http.proxy_from_env? # => true
  #   http.proxy_address   # => "example.com"
  #   # These use default values.
  #   http.proxy_port      # => 80
  #   http.proxy_user      # => nil
  #   http.proxy_pass      # => nil
  #
  # The \Gem::URI string may include proxy username, password, and port number:
  #
  #   ENV['http_proxy'] = 'http://pname:ppass@example.com:8000'
  #   http = Gem::Net::HTTP.new(hostname)
  #   http.proxy?          # => true
  #   http.proxy_from_env? # => true
  #   http.proxy_address   # => "example.com"
  #   http.proxy_port      # => 8000
  #   http.proxy_user      # => "pname"
  #   http.proxy_pass      # => "ppass"
  #
  # === Filtering Proxies
  #
  # With method Gem::Net::HTTP.new (but not Gem::Net::HTTP.start),
  # you can use argument +p_no_proxy+ to filter proxies:
  #
  # - Reject a certain address:
  #
  #     http = Gem::Net::HTTP.new('example.com', nil, 'proxy.example', 8000, 'pname', 'ppass', 'proxy.example')
  #     http.proxy_address # => nil
  #
  # - Reject certain domains or subdomains:
  #
  #     http = Gem::Net::HTTP.new('example.com', nil, 'my.proxy.example', 8000, 'pname', 'ppass', 'proxy.example')
  #     http.proxy_address # => nil
  #
  # - Reject certain addresses and port combinations:
  #
  #     http = Gem::Net::HTTP.new('example.com', nil, 'proxy.example', 8000, 'pname', 'ppass', 'proxy.example:1234')
  #     http.proxy_address # => "proxy.example"
  #
  #     http = Gem::Net::HTTP.new('example.com', nil, 'proxy.example', 8000, 'pname', 'ppass', 'proxy.example:8000')
  #     http.proxy_address # => nil
  #
  # - Reject a list of the types above delimited using a comma:
  #
  #     http = Gem::Net::HTTP.new('example.com', nil, 'proxy.example', 8000, 'pname', 'ppass', 'my.proxy,proxy.example:8000')
  #     http.proxy_address # => nil
  #
  #     http = Gem::Net::HTTP.new('example.com', nil, 'my.proxy', 8000, 'pname', 'ppass', 'my.proxy,proxy.example:8000')
  #     http.proxy_address # => nil
  #
  # == Compression and Decompression
  #
  # \Gem::Net::HTTP does not compress the body of a request before sending.
  #
  # By default, \Gem::Net::HTTP adds header <tt>'Accept-Encoding'</tt>
  # to a new {request object}[rdoc-ref:Gem::Net::HTTPRequest]:
  #
  #   Gem::Net::HTTP::Get.new(uri)['Accept-Encoding']
  #   # => "gzip;q=1.0,deflate;q=0.6,identity;q=0.3"
  #
  # This requests the server to zip-encode the response body if there is one;
  # the server is not required to do so.
  #
  # \Gem::Net::HTTP does not automatically decompress a response body
  # if the response has header <tt>'Content-Range'</tt>.
  #
  # Otherwise decompression (or not) depends on the value of header
  # {Content-Encoding}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#content-encoding-response-header]:
  #
  # - <tt>'deflate'</tt>, <tt>'gzip'</tt>, or <tt>'x-gzip'</tt>:
  #   decompresses the body and deletes the header.
  # - <tt>'none'</tt> or <tt>'identity'</tt>:
  #   does not decompress the body, but deletes the header.
  # - Any other value:
  #   leaves the body and header unchanged.
  #
  # == What's Here
  #
  # This is a categorized summary of methods and attributes.
  #
  # === \Gem::Net::HTTP Objects
  #
  # - {::new}[rdoc-ref:Gem::Net::HTTP.new]:
  #   Creates a new instance.
  # - {#inspect}[rdoc-ref:Gem::Net::HTTP#inspect]:
  #   Returns a string representation of +self+.
  #
  # === Sessions
  #
  # - {::start}[rdoc-ref:Gem::Net::HTTP.start]:
  #   Begins a new session in a new \Gem::Net::HTTP object.
  # - {#started?}[rdoc-ref:Gem::Net::HTTP#started?]
  #   (aliased as {#active?}[rdoc-ref:Gem::Net::HTTP#active?]):
  #   Returns whether in a session.
  # - {#finish}[rdoc-ref:Gem::Net::HTTP#finish]:
  #   Ends an active session.
  # - {#start}[rdoc-ref:Gem::Net::HTTP#start]:
  #   Begins a new session in an existing \Gem::Net::HTTP object (+self+).
  #
  # === Connections
  #
  # - {:continue_timeout}[rdoc-ref:Gem::Net::HTTP#continue_timeout]:
  #   Returns the continue timeout.
  # - {#continue_timeout=}[rdoc-ref:Gem::Net::HTTP#continue_timeout=]:
  #   Sets the continue timeout seconds.
  # - {:keep_alive_timeout}[rdoc-ref:Gem::Net::HTTP#keep_alive_timeout]:
  #   Returns the keep-alive timeout.
  # - {:keep_alive_timeout=}[rdoc-ref:Gem::Net::HTTP#keep_alive_timeout=]:
  #   Sets the keep-alive timeout.
  # - {:max_retries}[rdoc-ref:Gem::Net::HTTP#max_retries]:
  #   Returns the maximum retries.
  # - {#max_retries=}[rdoc-ref:Gem::Net::HTTP#max_retries=]:
  #   Sets the maximum retries.
  # - {:open_timeout}[rdoc-ref:Gem::Net::HTTP#open_timeout]:
  #   Returns the open timeout.
  # - {:open_timeout=}[rdoc-ref:Gem::Net::HTTP#open_timeout=]:
  #   Sets the open timeout.
  # - {:read_timeout}[rdoc-ref:Gem::Net::HTTP#read_timeout]:
  #   Returns the open timeout.
  # - {:read_timeout=}[rdoc-ref:Gem::Net::HTTP#read_timeout=]:
  #   Sets the read timeout.
  # - {:ssl_timeout}[rdoc-ref:Gem::Net::HTTP#ssl_timeout]:
  #   Returns the ssl timeout.
  # - {:ssl_timeout=}[rdoc-ref:Gem::Net::HTTP#ssl_timeout=]:
  #   Sets the ssl timeout.
  # - {:write_timeout}[rdoc-ref:Gem::Net::HTTP#write_timeout]:
  #   Returns the write timeout.
  # - {write_timeout=}[rdoc-ref:Gem::Net::HTTP#write_timeout=]:
  #   Sets the write timeout.
  #
  # === Requests
  #
  # - {::get}[rdoc-ref:Gem::Net::HTTP.get]:
  #   Sends a GET request and returns the string response body.
  # - {::get_print}[rdoc-ref:Gem::Net::HTTP.get_print]:
  #   Sends a GET request and write the string response body to $stdout.
  # - {::get_response}[rdoc-ref:Gem::Net::HTTP.get_response]:
  #   Sends a GET request and returns a response object.
  # - {::post_form}[rdoc-ref:Gem::Net::HTTP.post_form]:
  #   Sends a POST request with form data and returns a response object.
  # - {::post}[rdoc-ref:Gem::Net::HTTP.post]:
  #   Sends a POST request with data and returns a response object.
  # - {#copy}[rdoc-ref:Gem::Net::HTTP#copy]:
  #   Sends a COPY request and returns a response object.
  # - {#delete}[rdoc-ref:Gem::Net::HTTP#delete]:
  #   Sends a DELETE request and returns a response object.
  # - {#get}[rdoc-ref:Gem::Net::HTTP#get]:
  #   Sends a GET request and returns a response object.
  # - {#head}[rdoc-ref:Gem::Net::HTTP#head]:
  #   Sends a HEAD request and returns a response object.
  # - {#lock}[rdoc-ref:Gem::Net::HTTP#lock]:
  #   Sends a LOCK request and returns a response object.
  # - {#mkcol}[rdoc-ref:Gem::Net::HTTP#mkcol]:
  #   Sends a MKCOL request and returns a response object.
  # - {#move}[rdoc-ref:Gem::Net::HTTP#move]:
  #   Sends a MOVE request and returns a response object.
  # - {#options}[rdoc-ref:Gem::Net::HTTP#options]:
  #   Sends a OPTIONS request and returns a response object.
  # - {#patch}[rdoc-ref:Gem::Net::HTTP#patch]:
  #   Sends a PATCH request and returns a response object.
  # - {#post}[rdoc-ref:Gem::Net::HTTP#post]:
  #   Sends a POST request and returns a response object.
  # - {#propfind}[rdoc-ref:Gem::Net::HTTP#propfind]:
  #   Sends a PROPFIND request and returns a response object.
  # - {#proppatch}[rdoc-ref:Gem::Net::HTTP#proppatch]:
  #   Sends a PROPPATCH request and returns a response object.
  # - {#put}[rdoc-ref:Gem::Net::HTTP#put]:
  #   Sends a PUT request and returns a response object.
  # - {#request}[rdoc-ref:Gem::Net::HTTP#request]:
  #   Sends a request and returns a response object.
  # - {#request_get}[rdoc-ref:Gem::Net::HTTP#request_get]
  #   (aliased as {#get2}[rdoc-ref:Gem::Net::HTTP#get2]):
  #   Sends a GET request and forms a response object;
  #   if a block given, calls the block with the object,
  #   otherwise returns the object.
  # - {#request_head}[rdoc-ref:Gem::Net::HTTP#request_head]
  #   (aliased as {#head2}[rdoc-ref:Gem::Net::HTTP#head2]):
  #   Sends a HEAD request and forms a response object;
  #   if a block given, calls the block with the object,
  #   otherwise returns the object.
  # - {#request_post}[rdoc-ref:Gem::Net::HTTP#request_post]
  #   (aliased as {#post2}[rdoc-ref:Gem::Net::HTTP#post2]):
  #   Sends a POST request and forms a response object;
  #   if a block given, calls the block with the object,
  #   otherwise returns the object.
  # - {#send_request}[rdoc-ref:Gem::Net::HTTP#send_request]:
  #   Sends a request and returns a response object.
  # - {#trace}[rdoc-ref:Gem::Net::HTTP#trace]:
  #   Sends a TRACE request and returns a response object.
  # - {#unlock}[rdoc-ref:Gem::Net::HTTP#unlock]:
  #   Sends an UNLOCK request and returns a response object.
  #
  # === Responses
  #
  # - {:close_on_empty_response}[rdoc-ref:Gem::Net::HTTP#close_on_empty_response]:
  #   Returns whether to close connection on empty response.
  # - {:close_on_empty_response=}[rdoc-ref:Gem::Net::HTTP#close_on_empty_response=]:
  #   Sets whether to close connection on empty response.
  # - {:ignore_eof}[rdoc-ref:Gem::Net::HTTP#ignore_eof]:
  #   Returns whether to ignore end-of-file when reading a response body
  #   with <tt>Content-Length</tt> headers.
  # - {:ignore_eof=}[rdoc-ref:Gem::Net::HTTP#ignore_eof=]:
  #   Sets whether to ignore end-of-file when reading a response body
  #   with <tt>Content-Length</tt> headers.
  # - {:response_body_encoding}[rdoc-ref:Gem::Net::HTTP#response_body_encoding]:
  #   Returns the encoding to use for the response body.
  # - {#response_body_encoding=}[rdoc-ref:Gem::Net::HTTP#response_body_encoding=]:
  #   Sets the response body encoding.
  #
  # === Proxies
  #
  # - {:proxy_address}[rdoc-ref:Gem::Net::HTTP#proxy_address]:
  #   Returns the proxy address.
  # - {:proxy_address=}[rdoc-ref:Gem::Net::HTTP#proxy_address=]:
  #   Sets the proxy address.
  # - {::proxy_class?}[rdoc-ref:Gem::Net::HTTP.proxy_class?]:
  #   Returns whether +self+ is a proxy class.
  # - {#proxy?}[rdoc-ref:Gem::Net::HTTP#proxy?]:
  #   Returns whether +self+ has a proxy.
  # - {#proxy_address}[rdoc-ref:Gem::Net::HTTP#proxy_address]
  #   (aliased as {#proxyaddr}[rdoc-ref:Gem::Net::HTTP#proxyaddr]):
  #   Returns the proxy address.
  # - {#proxy_from_env?}[rdoc-ref:Gem::Net::HTTP#proxy_from_env?]:
  #   Returns whether the proxy is taken from an environment variable.
  # - {:proxy_from_env=}[rdoc-ref:Gem::Net::HTTP#proxy_from_env=]:
  #   Sets whether the proxy is to be taken from an environment variable.
  # - {:proxy_pass}[rdoc-ref:Gem::Net::HTTP#proxy_pass]:
  #   Returns the proxy password.
  # - {:proxy_pass=}[rdoc-ref:Gem::Net::HTTP#proxy_pass=]:
  #   Sets the proxy password.
  # - {:proxy_port}[rdoc-ref:Gem::Net::HTTP#proxy_port]:
  #   Returns the proxy port.
  # - {:proxy_port=}[rdoc-ref:Gem::Net::HTTP#proxy_port=]:
  #   Sets the proxy port.
  # - {#proxy_user}[rdoc-ref:Gem::Net::HTTP#proxy_user]:
  #   Returns the proxy user name.
  # - {:proxy_user=}[rdoc-ref:Gem::Net::HTTP#proxy_user=]:
  #   Sets the proxy user.
  #
  # === Security
  #
  # - {:ca_file}[rdoc-ref:Gem::Net::HTTP#ca_file]:
  #   Returns the path to a CA certification file.
  # - {:ca_file=}[rdoc-ref:Gem::Net::HTTP#ca_file=]:
  #   Sets the path to a CA certification file.
  # - {:ca_path}[rdoc-ref:Gem::Net::HTTP#ca_path]:
  #   Returns the path of to CA directory containing certification files.
  # - {:ca_path=}[rdoc-ref:Gem::Net::HTTP#ca_path=]:
  #   Sets the path of to CA directory containing certification files.
  # - {:cert}[rdoc-ref:Gem::Net::HTTP#cert]:
  #   Returns the OpenSSL::X509::Certificate object to be used for client certification.
  # - {:cert=}[rdoc-ref:Gem::Net::HTTP#cert=]:
  #   Sets the OpenSSL::X509::Certificate object to be used for client certification.
  # - {:cert_store}[rdoc-ref:Gem::Net::HTTP#cert_store]:
  #   Returns the X509::Store to be used for verifying peer certificate.
  # - {:cert_store=}[rdoc-ref:Gem::Net::HTTP#cert_store=]:
  #   Sets the X509::Store to be used for verifying peer certificate.
  # - {:ciphers}[rdoc-ref:Gem::Net::HTTP#ciphers]:
  #   Returns the available SSL ciphers.
  # - {:ciphers=}[rdoc-ref:Gem::Net::HTTP#ciphers=]:
  #   Sets the available SSL ciphers.
  # - {:extra_chain_cert}[rdoc-ref:Gem::Net::HTTP#extra_chain_cert]:
  #   Returns the extra X509 certificates to be added to the certificate chain.
  # - {:extra_chain_cert=}[rdoc-ref:Gem::Net::HTTP#extra_chain_cert=]:
  #   Sets the extra X509 certificates to be added to the certificate chain.
  # - {:key}[rdoc-ref:Gem::Net::HTTP#key]:
  #   Returns the OpenSSL::PKey::RSA or OpenSSL::PKey::DSA object.
  # - {:key=}[rdoc-ref:Gem::Net::HTTP#key=]:
  #   Sets the OpenSSL::PKey::RSA or OpenSSL::PKey::DSA object.
  # - {:max_version}[rdoc-ref:Gem::Net::HTTP#max_version]:
  #   Returns the maximum SSL version.
  # - {:max_version=}[rdoc-ref:Gem::Net::HTTP#max_version=]:
  #   Sets the maximum SSL version.
  # - {:min_version}[rdoc-ref:Gem::Net::HTTP#min_version]:
  #   Returns the minimum SSL version.
  # - {:min_version=}[rdoc-ref:Gem::Net::HTTP#min_version=]:
  #   Sets the minimum SSL version.
  # - {#peer_cert}[rdoc-ref:Gem::Net::HTTP#peer_cert]:
  #   Returns the X509 certificate chain for the session's socket peer.
  # - {:ssl_version}[rdoc-ref:Gem::Net::HTTP#ssl_version]:
  #   Returns the SSL version.
  # - {:ssl_version=}[rdoc-ref:Gem::Net::HTTP#ssl_version=]:
  #   Sets the SSL version.
  # - {#use_ssl=}[rdoc-ref:Gem::Net::HTTP#use_ssl=]:
  #   Sets whether a new session is to use Transport Layer Security.
  # - {#use_ssl?}[rdoc-ref:Gem::Net::HTTP#use_ssl?]:
  #   Returns whether +self+ uses SSL.
  # - {:verify_callback}[rdoc-ref:Gem::Net::HTTP#verify_callback]:
  #   Returns the callback for the server certification verification.
  # - {:verify_callback=}[rdoc-ref:Gem::Net::HTTP#verify_callback=]:
  #   Sets the callback for the server certification verification.
  # - {:verify_depth}[rdoc-ref:Gem::Net::HTTP#verify_depth]:
  #   Returns the maximum depth for the certificate chain verification.
  # - {:verify_depth=}[rdoc-ref:Gem::Net::HTTP#verify_depth=]:
  #   Sets the maximum depth for the certificate chain verification.
  # - {:verify_hostname}[rdoc-ref:Gem::Net::HTTP#verify_hostname]:
  #   Returns the flags for server the certification verification at the beginning of the SSL/TLS session.
  # - {:verify_hostname=}[rdoc-ref:Gem::Net::HTTP#verify_hostname=]:
  #   Sets he flags for server the certification verification at the beginning of the SSL/TLS session.
  # - {:verify_mode}[rdoc-ref:Gem::Net::HTTP#verify_mode]:
  #   Returns the flags for server the certification verification at the beginning of the SSL/TLS session.
  # - {:verify_mode=}[rdoc-ref:Gem::Net::HTTP#verify_mode=]:
  #   Sets the flags for server the certification verification at the beginning of the SSL/TLS session.
  #
  # === Addresses and Ports
  #
  # - {:address}[rdoc-ref:Gem::Net::HTTP#address]:
  #   Returns the string host name or host IP.
  # - {::default_port}[rdoc-ref:Gem::Net::HTTP.default_port]:
  #   Returns integer 80, the default port to use for HTTP requests.
  # - {::http_default_port}[rdoc-ref:Gem::Net::HTTP.http_default_port]:
  #   Returns integer 80, the default port to use for HTTP requests.
  # - {::https_default_port}[rdoc-ref:Gem::Net::HTTP.https_default_port]:
  #   Returns integer 443, the default port to use for HTTPS requests.
  # - {#ipaddr}[rdoc-ref:Gem::Net::HTTP#ipaddr]:
  #   Returns the IP address for the connection.
  # - {#ipaddr=}[rdoc-ref:Gem::Net::HTTP#ipaddr=]:
  #   Sets the IP address for the connection.
  # - {:local_host}[rdoc-ref:Gem::Net::HTTP#local_host]:
  #   Returns the string local host used to establish the connection.
  # - {:local_host=}[rdoc-ref:Gem::Net::HTTP#local_host=]:
  #   Sets the string local host used to establish the connection.
  # - {:local_port}[rdoc-ref:Gem::Net::HTTP#local_port]:
  #   Returns the integer local port used to establish the connection.
  # - {:local_port=}[rdoc-ref:Gem::Net::HTTP#local_port=]:
  #   Sets the integer local port used to establish the connection.
  # - {:port}[rdoc-ref:Gem::Net::HTTP#port]:
  #   Returns the integer port number.
  #
  # === \HTTP Version
  #
  # - {::version_1_2?}[rdoc-ref:Gem::Net::HTTP.version_1_2?]
  #   (aliased as {::is_version_1_2?}[rdoc-ref:Gem::Net::HTTP.is_version_1_2?]
  #   and {::version_1_2}[rdoc-ref:Gem::Net::HTTP.version_1_2]):
  #   Returns true; retained for compatibility.
  #
  # === Debugging
  #
  # - {#set_debug_output}[rdoc-ref:Gem::Net::HTTP#set_debug_output]:
  #   Sets the output stream for debugging.
  #
  class HTTP < Protocol

    # :stopdoc:
    VERSION = "0.4.1"
    HTTPVersion = '1.1'
    begin
      require 'zlib'
      HAVE_ZLIB=true
    rescue LoadError
      HAVE_ZLIB=false
    end
    # :startdoc:

    # Returns +true+; retained for compatibility.
    def HTTP.version_1_2
      true
    end

    # Returns +true+; retained for compatibility.
    def HTTP.version_1_2?
      true
    end

    # Returns +false+; retained for compatibility.
    def HTTP.version_1_1?  #:nodoc:
      false
    end

    class << HTTP
      alias is_version_1_1? version_1_1?   #:nodoc:
      alias is_version_1_2? version_1_2?   #:nodoc:
    end

    # :call-seq:
    #   Gem::Net::HTTP.get_print(hostname, path, port = 80) -> nil
    #   Gem::Net::HTTP:get_print(uri, headers = {}, port = uri.port) -> nil
    #
    # Like Gem::Net::HTTP.get, but writes the returned body to $stdout;
    # returns +nil+.
    def HTTP.get_print(uri_or_host, path_or_headers = nil, port = nil)
      get_response(uri_or_host, path_or_headers, port) {|res|
        res.read_body do |chunk|
          $stdout.print chunk
        end
      }
      nil
    end

    # :call-seq:
    #   Gem::Net::HTTP.get(hostname, path, port = 80) -> body
    #   Gem::Net::HTTP:get(uri, headers = {}, port = uri.port) -> body
    #
    # Sends a GET request and returns the \HTTP response body as a string.
    #
    # With string arguments +hostname+ and +path+:
    #
    #   hostname = 'jsonplaceholder.typicode.com'
    #   path = '/todos/1'
    #   puts Gem::Net::HTTP.get(hostname, path)
    #
    # Output:
    #
    #   {
    #     "userId": 1,
    #     "id": 1,
    #     "title": "delectus aut autem",
    #     "completed": false
    #   }
    #
    # With URI object +uri+ and optional hash argument +headers+:
    #
    #   uri = Gem::URI('https://jsonplaceholder.typicode.com/todos/1')
    #   headers = {'Content-type' => 'application/json; charset=UTF-8'}
    #   Gem::Net::HTTP.get(uri, headers)
    #
    # Related:
    #
    # - Gem::Net::HTTP::Get: request class for \HTTP method +GET+.
    # - Gem::Net::HTTP#get: convenience method for \HTTP method +GET+.
    #
    def HTTP.get(uri_or_host, path_or_headers = nil, port = nil)
      get_response(uri_or_host, path_or_headers, port).body
    end

    # :call-seq:
    #   Gem::Net::HTTP.get_response(hostname, path, port = 80) -> http_response
    #   Gem::Net::HTTP:get_response(uri, headers = {}, port = uri.port) -> http_response
    #
    # Like Gem::Net::HTTP.get, but returns a Gem::Net::HTTPResponse object
    # instead of the body string.
    def HTTP.get_response(uri_or_host, path_or_headers = nil, port = nil, &block)
      if path_or_headers && !path_or_headers.is_a?(Hash)
        host = uri_or_host
        path = path_or_headers
        new(host, port || HTTP.default_port).start {|http|
          return http.request_get(path, &block)
        }
      else
        uri = uri_or_host
        headers = path_or_headers
        start(uri.hostname, uri.port,
              :use_ssl => uri.scheme == 'https') {|http|
          return http.request_get(uri, headers, &block)
        }
      end
    end

    # Posts data to a host; returns a Gem::Net::HTTPResponse object.
    #
    # Argument +url+ must be a URL;
    # argument +data+ must be a string:
    #
    #   _uri = uri.dup
    #   _uri.path = '/posts'
    #   data = '{"title": "foo", "body": "bar", "userId": 1}'
    #   headers = {'content-type': 'application/json'}
    #   res = Gem::Net::HTTP.post(_uri, data, headers) # => #<Gem::Net::HTTPCreated 201 Created readbody=true>
    #   puts res.body
    #
    # Output:
    #
    #   {
    #     "title": "foo",
    #     "body": "bar",
    #     "userId": 1,
    #     "id": 101
    #   }
    #
    # Related:
    #
    # - Gem::Net::HTTP::Post: request class for \HTTP method +POST+.
    # - Gem::Net::HTTP#post: convenience method for \HTTP method +POST+.
    #
    def HTTP.post(url, data, header = nil)
      start(url.hostname, url.port,
            :use_ssl => url.scheme == 'https' ) {|http|
        http.post(url, data, header)
      }
    end

    # Posts data to a host; returns a Gem::Net::HTTPResponse object.
    #
    # Argument +url+ must be a URI;
    # argument +data+ must be a hash:
    #
    #   _uri = uri.dup
    #   _uri.path = '/posts'
    #   data = {title: 'foo', body: 'bar', userId: 1}
    #   res = Gem::Net::HTTP.post_form(_uri, data) # => #<Gem::Net::HTTPCreated 201 Created readbody=true>
    #   puts res.body
    #
    # Output:
    #
    #   {
    #     "title": "foo",
    #     "body": "bar",
    #     "userId": "1",
    #     "id": 101
    #   }
    #
    def HTTP.post_form(url, params)
      req = Post.new(url)
      req.form_data = params
      req.basic_auth url.user, url.password if url.user
      start(url.hostname, url.port,
            :use_ssl => url.scheme == 'https' ) {|http|
        http.request(req)
      }
    end

    #
    # \HTTP session management
    #

    # Returns integer +80+, the default port to use for \HTTP requests:
    #
    #   Gem::Net::HTTP.default_port # => 80
    #
    def HTTP.default_port
      http_default_port()
    end

    # Returns integer +80+, the default port to use for \HTTP requests:
    #
    #   Gem::Net::HTTP.http_default_port # => 80
    #
    def HTTP.http_default_port
      80
    end

    # Returns integer +443+, the default port to use for HTTPS requests:
    #
    #   Gem::Net::HTTP.https_default_port # => 443
    #
    def HTTP.https_default_port
      443
    end

    def HTTP.socket_type   #:nodoc: obsolete
      BufferedIO
    end

    # :call-seq:
    #   HTTP.start(address, port = nil, p_addr = :ENV, p_port = nil, p_user = nil, p_pass = nil, opts) -> http
    #   HTTP.start(address, port = nil, p_addr = :ENV, p_port = nil, p_user = nil, p_pass = nil, opts) {|http| ... } -> object
    #
    # Creates a new \Gem::Net::HTTP object, +http+, via \Gem::Net::HTTP.new:
    #
    # - For arguments +address+ and +port+, see Gem::Net::HTTP.new.
    # - For proxy-defining arguments +p_addr+ through +p_pass+,
    #   see {Proxy Server}[rdoc-ref:Gem::Net::HTTP@Proxy+Server].
    # - For argument +opts+, see below.
    #
    # With no block given:
    #
    # - Calls <tt>http.start</tt> with no block (see #start),
    #   which opens a TCP connection and \HTTP session.
    # - Returns +http+.
    # - The caller should call #finish to close the session:
    #
    #     http = Gem::Net::HTTP.start(hostname)
    #     http.started? # => true
    #     http.finish
    #     http.started? # => false
    #
    # With a block given:
    #
    # - Calls <tt>http.start</tt> with the block (see #start), which:
    #
    #   - Opens a TCP connection and \HTTP session.
    #   - Calls the block,
    #     which may make any number of requests to the host.
    #   - Closes the \HTTP session and TCP connection on block exit.
    #   - Returns the block's value +object+.
    #
    # - Returns +object+.
    #
    # Example:
    #
    #   hostname = 'jsonplaceholder.typicode.com'
    #   Gem::Net::HTTP.start(hostname) do |http|
    #     puts http.get('/todos/1').body
    #     puts http.get('/todos/2').body
    #   end
    #
    # Output:
    #
    #   {
    #     "userId": 1,
    #     "id": 1,
    #     "title": "delectus aut autem",
    #     "completed": false
    #   }
    #   {
    #     "userId": 1,
    #     "id": 2,
    #     "title": "quis ut nam facilis et officia qui",
    #     "completed": false
    #   }
    #
    # If the last argument given is a hash, it is the +opts+ hash,
    # where each key is a method or accessor to be called,
    # and its value is the value to be set.
    #
    # The keys may include:
    #
    # - #ca_file
    # - #ca_path
    # - #cert
    # - #cert_store
    # - #ciphers
    # - #close_on_empty_response
    # - +ipaddr+ (calls #ipaddr=)
    # - #keep_alive_timeout
    # - #key
    # - #open_timeout
    # - #read_timeout
    # - #ssl_timeout
    # - #ssl_version
    # - +use_ssl+ (calls #use_ssl=)
    # - #verify_callback
    # - #verify_depth
    # - #verify_mode
    # - #write_timeout
    #
    # Note: If +port+ is +nil+ and <tt>opts[:use_ssl]</tt> is a truthy value,
    # the value passed to +new+ is Gem::Net::HTTP.https_default_port, not +port+.
    #
    def HTTP.start(address, *arg, &block) # :yield: +http+
      arg.pop if opt = Hash.try_convert(arg[-1])
      port, p_addr, p_port, p_user, p_pass = *arg
      p_addr = :ENV if arg.size < 2
      port = https_default_port if !port && opt && opt[:use_ssl]
      http = new(address, port, p_addr, p_port, p_user, p_pass)
      http.ipaddr = opt[:ipaddr] if opt && opt[:ipaddr]

      if opt
        if opt[:use_ssl]
          opt = {verify_mode: OpenSSL::SSL::VERIFY_PEER}.update(opt)
        end
        http.methods.grep(/\A(\w+)=\z/) do |meth|
          key = $1.to_sym
          opt.key?(key) or next
          http.__send__(meth, opt[key])
        end
      end

      http.start(&block)
    end

    class << HTTP
      alias newobj new # :nodoc:
    end

    # Returns a new \Gem::Net::HTTP object +http+
    # (but does not open a TCP connection or \HTTP session).
    #
    # With only string argument +address+ given
    # (and <tt>ENV['http_proxy']</tt> undefined or +nil+),
    # the returned +http+:
    #
    # - Has the given address.
    # - Has the default port number, Gem::Net::HTTP.default_port (80).
    # - Has no proxy.
    #
    # Example:
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   # => #<Gem::Net::HTTP jsonplaceholder.typicode.com:80 open=false>
    #   http.address # => "jsonplaceholder.typicode.com"
    #   http.port    # => 80
    #   http.proxy?  # => false
    #
    # With integer argument +port+ also given,
    # the returned +http+ has the given port:
    #
    #   http = Gem::Net::HTTP.new(hostname, 8000)
    #   # => #<Gem::Net::HTTP jsonplaceholder.typicode.com:8000 open=false>
    #   http.port # => 8000
    #
    # For proxy-defining arguments +p_addr+ through +p_no_proxy+,
    # see {Proxy Server}[rdoc-ref:Gem::Net::HTTP@Proxy+Server].
    #
    def HTTP.new(address, port = nil, p_addr = :ENV, p_port = nil, p_user = nil, p_pass = nil, p_no_proxy = nil)
      http = super address, port

      if proxy_class? then # from Gem::Net::HTTP::Proxy()
        http.proxy_from_env = @proxy_from_env
        http.proxy_address  = @proxy_address
        http.proxy_port     = @proxy_port
        http.proxy_user     = @proxy_user
        http.proxy_pass     = @proxy_pass
      elsif p_addr == :ENV then
        http.proxy_from_env = true
      else
        if p_addr && p_no_proxy && !Gem::URI::Generic.use_proxy?(address, address, port, p_no_proxy)
          p_addr = nil
          p_port = nil
        end
        http.proxy_address = p_addr
        http.proxy_port    = p_port || default_port
        http.proxy_user    = p_user
        http.proxy_pass    = p_pass
      end

      http
    end

    # Creates a new \Gem::Net::HTTP object for the specified server address,
    # without opening the TCP connection or initializing the \HTTP session.
    # The +address+ should be a DNS hostname or IP address.
    def initialize(address, port = nil) # :nodoc:
      @address = address
      @port    = (port || HTTP.default_port)
      @ipaddr = nil
      @local_host = nil
      @local_port = nil
      @curr_http_version = HTTPVersion
      @keep_alive_timeout = 2
      @last_communicated = nil
      @close_on_empty_response = false
      @socket  = nil
      @started = false
      @open_timeout = 60
      @read_timeout = 60
      @write_timeout = 60
      @continue_timeout = nil
      @max_retries = 1
      @debug_output = nil
      @response_body_encoding = false
      @ignore_eof = true

      @proxy_from_env = false
      @proxy_uri      = nil
      @proxy_address  = nil
      @proxy_port     = nil
      @proxy_user     = nil
      @proxy_pass     = nil

      @use_ssl = false
      @ssl_context = nil
      @ssl_session = nil
      @sspi_enabled = false
      SSL_IVNAMES.each do |ivname|
        instance_variable_set ivname, nil
      end
    end

    # Returns a string representation of +self+:
    #
    #   Gem::Net::HTTP.new(hostname).inspect
    #   # => "#<Gem::Net::HTTP jsonplaceholder.typicode.com:80 open=false>"
    #
    def inspect
      "#<#{self.class} #{@address}:#{@port} open=#{started?}>"
    end

    # *WARNING* This method opens a serious security hole.
    # Never use this method in production code.
    #
    # Sets the output stream for debugging:
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   File.open('t.tmp', 'w') do |file|
    #     http.set_debug_output(file)
    #     http.start
    #     http.get('/nosuch/1')
    #     http.finish
    #   end
    #   puts File.read('t.tmp')
    #
    # Output:
    #
    #   opening connection to jsonplaceholder.typicode.com:80...
    #   opened
    #   <- "GET /nosuch/1 HTTP/1.1\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept: */*\r\nUser-Agent: Ruby\r\nHost: jsonplaceholder.typicode.com\r\n\r\n"
    #   -> "HTTP/1.1 404 Not Found\r\n"
    #   -> "Date: Mon, 12 Dec 2022 21:14:11 GMT\r\n"
    #   -> "Content-Type: application/json; charset=utf-8\r\n"
    #   -> "Content-Length: 2\r\n"
    #   -> "Connection: keep-alive\r\n"
    #   -> "X-Powered-By: Express\r\n"
    #   -> "X-Ratelimit-Limit: 1000\r\n"
    #   -> "X-Ratelimit-Remaining: 999\r\n"
    #   -> "X-Ratelimit-Reset: 1670879660\r\n"
    #   -> "Vary: Origin, Accept-Encoding\r\n"
    #   -> "Access-Control-Allow-Credentials: true\r\n"
    #   -> "Cache-Control: max-age=43200\r\n"
    #   -> "Pragma: no-cache\r\n"
    #   -> "Expires: -1\r\n"
    #   -> "X-Content-Type-Options: nosniff\r\n"
    #   -> "Etag: W/\"2-vyGp6PvFo4RvsFtPoIWeCReyIC8\"\r\n"
    #   -> "Via: 1.1 vegur\r\n"
    #   -> "CF-Cache-Status: MISS\r\n"
    #   -> "Server-Timing: cf-q-config;dur=1.3000000762986e-05\r\n"
    #   -> "Report-To: {\"endpoints\":[{\"url\":\"https:\\/\\/a.nel.cloudflare.com\\/report\\/v3?s=yOr40jo%2BwS1KHzhTlVpl54beJ5Wx2FcG4gGV0XVrh3X9OlR5q4drUn2dkt5DGO4GDcE%2BVXT7CNgJvGs%2BZleIyMu8CLieFiDIvOviOY3EhHg94m0ZNZgrEdpKD0S85S507l1vsEwEHkoTm%2Ff19SiO\"}],\"group\":\"cf-nel\",\"max_age\":604800}\r\n"
    #   -> "NEL: {\"success_fraction\":0,\"report_to\":\"cf-nel\",\"max_age\":604800}\r\n"
    #   -> "Server: cloudflare\r\n"
    #   -> "CF-RAY: 778977dc484ce591-DFW\r\n"
    #   -> "alt-svc: h3=\":443\"; ma=86400, h3-29=\":443\"; ma=86400\r\n"
    #   -> "\r\n"
    #   reading 2 bytes...
    #   -> "{}"
    #   read 2 bytes
    #   Conn keep-alive
    #
    def set_debug_output(output)
      warn 'Gem::Net::HTTP#set_debug_output called after HTTP started', uplevel: 1 if started?
      @debug_output = output
    end

    # Returns the string host name or host IP given as argument +address+ in ::new.
    attr_reader :address

    # Returns the integer port number given as argument +port+ in ::new.
    attr_reader :port

    # Sets or returns the string local host used to establish the connection;
    # initially +nil+.
    attr_accessor :local_host

    # Sets or returns the integer local port used to establish the connection;
    # initially +nil+.
    attr_accessor :local_port

    # Returns the encoding to use for the response body;
    # see #response_body_encoding=.
    attr_reader :response_body_encoding

    # Sets the encoding to be used for the response body;
    # returns the encoding.
    #
    # The given +value+ may be:
    #
    # - An Encoding object.
    # - The name of an encoding.
    # - An alias for an encoding name.
    #
    # See {Encoding}[rdoc-ref:Encoding].
    #
    # Examples:
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.response_body_encoding = Encoding::US_ASCII # => #<Encoding:US-ASCII>
    #   http.response_body_encoding = 'US-ASCII'         # => "US-ASCII"
    #   http.response_body_encoding = 'ASCII'            # => "ASCII"
    #
    def response_body_encoding=(value)
      value = Encoding.find(value) if value.is_a?(String)
      @response_body_encoding = value
    end

    # Sets whether to determine the proxy from environment variable
    # '<tt>ENV['http_proxy']</tt>';
    # see {Proxy Using ENV['http_proxy']}[rdoc-ref:Gem::Net::HTTP@Proxy+Using+-27ENV-5B-27http_proxy-27-5D-27].
    attr_writer :proxy_from_env

    # Sets the proxy address;
    # see {Proxy Server}[rdoc-ref:Gem::Net::HTTP@Proxy+Server].
    attr_writer :proxy_address

    # Sets the proxy port;
    # see {Proxy Server}[rdoc-ref:Gem::Net::HTTP@Proxy+Server].
    attr_writer :proxy_port

    # Sets the proxy user;
    # see {Proxy Server}[rdoc-ref:Gem::Net::HTTP@Proxy+Server].
    attr_writer :proxy_user

    # Sets the proxy password;
    # see {Proxy Server}[rdoc-ref:Gem::Net::HTTP@Proxy+Server].
    attr_writer :proxy_pass

    # Returns the IP address for the connection.
    #
    # If the session has not been started,
    # returns the value set by #ipaddr=,
    # or +nil+ if it has not been set:
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.ipaddr # => nil
    #   http.ipaddr = '172.67.155.76'
    #   http.ipaddr # => "172.67.155.76"
    #
    # If the session has been started,
    # returns the IP address from the socket:
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.start
    #   http.ipaddr # => "172.67.155.76"
    #   http.finish
    #
    def ipaddr
      started? ?  @socket.io.peeraddr[3] : @ipaddr
    end

    # Sets the IP address for the connection:
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.ipaddr # => nil
    #   http.ipaddr = '172.67.155.76'
    #   http.ipaddr # => "172.67.155.76"
    #
    # The IP address may not be set if the session has been started.
    def ipaddr=(addr)
      raise IOError, "ipaddr value changed, but session already started" if started?
      @ipaddr = addr
    end

    # Sets or returns the numeric (\Integer or \Float) number of seconds
    # to wait for a connection to open;
    # initially 60.
    # If the connection is not made in the given interval,
    # an exception is raised.
    attr_accessor :open_timeout

    # Returns the numeric (\Integer or \Float) number of seconds
    # to wait for one block to be read (via one read(2) call);
    # see #read_timeout=.
    attr_reader :read_timeout

    # Returns the numeric (\Integer or \Float) number of seconds
    # to wait for one block to be written (via one write(2) call);
    # see #write_timeout=.
    attr_reader :write_timeout

    # Sets the maximum number of times to retry an idempotent request in case of
    # \Gem::Net::ReadTimeout, IOError, EOFError, Errno::ECONNRESET,
    # Errno::ECONNABORTED, Errno::EPIPE, OpenSSL::SSL::SSLError,
    # Gem::Timeout::Error.
    # The initial value is 1.
    #
    # Argument +retries+ must be a non-negative numeric value:
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.max_retries = 2   # => 2
    #   http.max_retries       # => 2
    #
    def max_retries=(retries)
      retries = retries.to_int
      if retries < 0
        raise ArgumentError, 'max_retries should be non-negative integer number'
      end
      @max_retries = retries
    end

    # Returns the maximum number of times to retry an idempotent request;
    # see #max_retries=.
    attr_reader :max_retries

    # Sets the read timeout, in seconds, for +self+ to integer +sec+;
    # the initial value is 60.
    #
    # Argument +sec+ must be a non-negative numeric value:
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.read_timeout # => 60
    #   http.get('/todos/1') # => #<Gem::Net::HTTPOK 200 OK readbody=true>
    #   http.read_timeout = 0
    #   http.get('/todos/1') # Raises Gem::Net::ReadTimeout.
    #
    def read_timeout=(sec)
      @socket.read_timeout = sec if @socket
      @read_timeout = sec
    end

    # Sets the write timeout, in seconds, for +self+ to integer +sec+;
    # the initial value is 60.
    #
    # Argument +sec+ must be a non-negative numeric value:
    #
    #   _uri = uri.dup
    #   _uri.path = '/posts'
    #   body = 'bar' * 200000
    #   data = <<EOF
    #   {"title": "foo", "body": "#{body}", "userId": "1"}
    #   EOF
    #   headers = {'content-type': 'application/json'}
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.write_timeout # => 60
    #   http.post(_uri.path, data, headers)
    #   # => #<Gem::Net::HTTPCreated 201 Created readbody=true>
    #   http.write_timeout = 0
    #   http.post(_uri.path, data, headers) # Raises Gem::Net::WriteTimeout.
    #
    def write_timeout=(sec)
      @socket.write_timeout = sec if @socket
      @write_timeout = sec
    end

    # Returns the continue timeout value;
    # see continue_timeout=.
    attr_reader :continue_timeout

    # Sets the continue timeout value,
    # which is the number of seconds to wait for an expected 100 Continue response.
    # If the \HTTP object does not receive a response in this many seconds
    # it sends the request body.
    def continue_timeout=(sec)
      @socket.continue_timeout = sec if @socket
      @continue_timeout = sec
    end

    # Sets or returns the numeric (\Integer or \Float) number of seconds
    # to keep the connection open after a request is sent;
    # initially 2.
    # If a new request is made during the given interval,
    # the still-open connection is used;
    # otherwise the connection will have been closed
    # and a new connection is opened.
    attr_accessor :keep_alive_timeout

    # Sets or returns whether to ignore end-of-file when reading a response body
    # with <tt>Content-Length</tt> headers;
    # initially +true+.
    attr_accessor :ignore_eof

    # Returns +true+ if the \HTTP session has been started:
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.started? # => false
    #   http.start
    #   http.started? # => true
    #   http.finish # => nil
    #   http.started? # => false
    #
    #   Gem::Net::HTTP.start(hostname) do |http|
    #     http.started?
    #   end # => true
    #   http.started? # => false
    #
    def started?
      @started
    end

    alias active? started?   #:nodoc: obsolete

    # Sets or returns whether to close the connection when the response is empty;
    # initially +false+.
    attr_accessor :close_on_empty_response

    # Returns +true+ if +self+ uses SSL, +false+ otherwise.
    # See Gem::Net::HTTP#use_ssl=.
    def use_ssl?
      @use_ssl
    end

    # Sets whether a new session is to use
    # {Transport Layer Security}[https://en.wikipedia.org/wiki/Transport_Layer_Security]:
    #
    # Raises IOError if attempting to change during a session.
    #
    # Raises OpenSSL::SSL::SSLError if the port is not an HTTPS port.
    def use_ssl=(flag)
      flag = flag ? true : false
      if started? and @use_ssl != flag
        raise IOError, "use_ssl value changed, but session already started"
      end
      @use_ssl = flag
    end

    SSL_IVNAMES = [
      :@ca_file,
      :@ca_path,
      :@cert,
      :@cert_store,
      :@ciphers,
      :@extra_chain_cert,
      :@key,
      :@ssl_timeout,
      :@ssl_version,
      :@min_version,
      :@max_version,
      :@verify_callback,
      :@verify_depth,
      :@verify_mode,
      :@verify_hostname,
    ] # :nodoc:
    SSL_ATTRIBUTES = [
      :ca_file,
      :ca_path,
      :cert,
      :cert_store,
      :ciphers,
      :extra_chain_cert,
      :key,
      :ssl_timeout,
      :ssl_version,
      :min_version,
      :max_version,
      :verify_callback,
      :verify_depth,
      :verify_mode,
      :verify_hostname,
    ] # :nodoc:

    # Sets or returns the path to a CA certification file in PEM format.
    attr_accessor :ca_file

    # Sets or returns the path of to CA directory
    # containing certification files in PEM format.
    attr_accessor :ca_path

    # Sets or returns the OpenSSL::X509::Certificate object
    # to be used for client certification.
    attr_accessor :cert

    # Sets or returns the X509::Store to be used for verifying peer certificate.
    attr_accessor :cert_store

    # Sets or returns the available SSL ciphers.
    # See {OpenSSL::SSL::SSLContext#ciphers=}[rdoc-ref:OpenSSL::SSL::SSLContext#ciphers-3D].
    attr_accessor :ciphers

    # Sets or returns the extra X509 certificates to be added to the certificate chain.
    # See {OpenSSL::SSL::SSLContext#add_certificate}[rdoc-ref:OpenSSL::SSL::SSLContext#add_certificate].
    attr_accessor :extra_chain_cert

    # Sets or returns the OpenSSL::PKey::RSA or OpenSSL::PKey::DSA object.
    attr_accessor :key

    # Sets or returns the SSL timeout seconds.
    attr_accessor :ssl_timeout

    # Sets or returns the SSL version.
    # See {OpenSSL::SSL::SSLContext#ssl_version=}[rdoc-ref:OpenSSL::SSL::SSLContext#ssl_version-3D].
    attr_accessor :ssl_version

    # Sets or returns the minimum SSL version.
    # See {OpenSSL::SSL::SSLContext#min_version=}[rdoc-ref:OpenSSL::SSL::SSLContext#min_version-3D].
    attr_accessor :min_version

    # Sets or returns the maximum SSL version.
    # See {OpenSSL::SSL::SSLContext#max_version=}[rdoc-ref:OpenSSL::SSL::SSLContext#max_version-3D].
    attr_accessor :max_version

    # Sets or returns the callback for the server certification verification.
    attr_accessor :verify_callback

    # Sets or returns the maximum depth for the certificate chain verification.
    attr_accessor :verify_depth

    # Sets or returns the flags for server the certification verification
    # at the beginning of the SSL/TLS session.
    # OpenSSL::SSL::VERIFY_NONE or OpenSSL::SSL::VERIFY_PEER are acceptable.
    attr_accessor :verify_mode

    # Sets or returns whether to verify that the server certificate is valid
    # for the hostname.
    # See {OpenSSL::SSL::SSLContext#verify_hostname=}[rdoc-ref:OpenSSL::SSL::SSLContext#attribute-i-verify_mode].
    attr_accessor :verify_hostname

    # Returns the X509 certificate chain (an array of strings)
    # for the session's socket peer,
    # or +nil+ if none.
    def peer_cert
      if not use_ssl? or not @socket
        return nil
      end
      @socket.io.peer_cert
    end

    # Starts an \HTTP session.
    #
    # Without a block, returns +self+:
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   # => #<Gem::Net::HTTP jsonplaceholder.typicode.com:80 open=false>
    #   http.start
    #   # => #<Gem::Net::HTTP jsonplaceholder.typicode.com:80 open=true>
    #   http.started? # => true
    #   http.finish
    #
    # With a block, calls the block with +self+,
    # finishes the session when the block exits,
    # and returns the block's value:
    #
    #   http.start do |http|
    #     http
    #   end
    #   # => #<Gem::Net::HTTP jsonplaceholder.typicode.com:80 open=false>
    #   http.started? # => false
    #
    def start  # :yield: http
      raise IOError, 'HTTP session already opened' if @started
      if block_given?
        begin
          do_start
          return yield(self)
        ensure
          do_finish
        end
      end
      do_start
      self
    end

    def do_start
      connect
      @started = true
    end
    private :do_start

    def connect
      if use_ssl?
        # reference early to load OpenSSL before connecting,
        # as OpenSSL may take time to load.
        @ssl_context = OpenSSL::SSL::SSLContext.new
      end

      if proxy? then
        conn_addr = proxy_address
        conn_port = proxy_port
      else
        conn_addr = conn_address
        conn_port = port
      end

      debug "opening connection to #{conn_addr}:#{conn_port}..."
      s = Gem::Timeout.timeout(@open_timeout, Gem::Net::OpenTimeout) {
        begin
          TCPSocket.open(conn_addr, conn_port, @local_host, @local_port)
        rescue => e
          raise e, "Failed to open TCP connection to " +
            "#{conn_addr}:#{conn_port} (#{e.message})"
        end
      }
      s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      debug "opened"
      if use_ssl?
        if proxy?
          plain_sock = BufferedIO.new(s, read_timeout: @read_timeout,
                                      write_timeout: @write_timeout,
                                      continue_timeout: @continue_timeout,
                                      debug_output: @debug_output)
          buf = +"CONNECT #{conn_address}:#{@port} HTTP/#{HTTPVersion}\r\n" \
            "Host: #{@address}:#{@port}\r\n"
          if proxy_user
            credential = ["#{proxy_user}:#{proxy_pass}"].pack('m0')
            buf << "Proxy-Authorization: Basic #{credential}\r\n"
          end
          buf << "\r\n"
          plain_sock.write(buf)
          HTTPResponse.read_new(plain_sock).value
          # assuming nothing left in buffers after successful CONNECT response
        end

        ssl_parameters = Hash.new
        iv_list = instance_variables
        SSL_IVNAMES.each_with_index do |ivname, i|
          if iv_list.include?(ivname)
            value = instance_variable_get(ivname)
            unless value.nil?
              ssl_parameters[SSL_ATTRIBUTES[i]] = value
            end
          end
        end
        @ssl_context.set_params(ssl_parameters)
        unless @ssl_context.session_cache_mode.nil? # a dummy method on JRuby
          @ssl_context.session_cache_mode =
              OpenSSL::SSL::SSLContext::SESSION_CACHE_CLIENT |
                  OpenSSL::SSL::SSLContext::SESSION_CACHE_NO_INTERNAL_STORE
        end
        if @ssl_context.respond_to?(:session_new_cb) # not implemented under JRuby
          @ssl_context.session_new_cb = proc {|sock, sess| @ssl_session = sess }
        end

        # Still do the post_connection_check below even if connecting
        # to IP address
        verify_hostname = @ssl_context.verify_hostname

        # Server Name Indication (SNI) RFC 3546/6066
        case @address
        when Gem::Resolv::IPv4::Regex, Gem::Resolv::IPv6::Regex
          # don't set SNI, as IP addresses in SNI is not valid
          # per RFC 6066, section 3.

          # Avoid openssl warning
          @ssl_context.verify_hostname = false
        else
          ssl_host_address = @address
        end

        debug "starting SSL for #{conn_addr}:#{conn_port}..."
        s = OpenSSL::SSL::SSLSocket.new(s, @ssl_context)
        s.sync_close = true
        s.hostname = ssl_host_address if s.respond_to?(:hostname=) && ssl_host_address

        if @ssl_session and
           Process.clock_gettime(Process::CLOCK_REALTIME) < @ssl_session.time.to_f + @ssl_session.timeout
          s.session = @ssl_session
        end
        ssl_socket_connect(s, @open_timeout)
        if (@ssl_context.verify_mode != OpenSSL::SSL::VERIFY_NONE) && verify_hostname
          s.post_connection_check(@address)
        end
        debug "SSL established, protocol: #{s.ssl_version}, cipher: #{s.cipher[0]}"
      end
      @socket = BufferedIO.new(s, read_timeout: @read_timeout,
                               write_timeout: @write_timeout,
                               continue_timeout: @continue_timeout,
                               debug_output: @debug_output)
      @last_communicated = nil
      on_connect
    rescue => exception
      if s
        debug "Conn close because of connect error #{exception}"
        s.close
      end
      raise
    end
    private :connect

    def on_connect
    end
    private :on_connect

    # Finishes the \HTTP session:
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.start
    #   http.started? # => true
    #   http.finish   # => nil
    #   http.started? # => false
    #
    # Raises IOError if not in a session.
    def finish
      raise IOError, 'HTTP session not yet started' unless started?
      do_finish
    end

    def do_finish
      @started = false
      @socket.close if @socket
      @socket = nil
    end
    private :do_finish

    #
    # proxy
    #

    public

    # no proxy
    @is_proxy_class = false
    @proxy_from_env = false
    @proxy_addr = nil
    @proxy_port = nil
    @proxy_user = nil
    @proxy_pass = nil

    # Creates an \HTTP proxy class which behaves like \Gem::Net::HTTP, but
    # performs all access via the specified proxy.
    #
    # This class is obsolete.  You may pass these same parameters directly to
    # \Gem::Net::HTTP.new.  See Gem::Net::HTTP.new for details of the arguments.
    def HTTP.Proxy(p_addr = :ENV, p_port = nil, p_user = nil, p_pass = nil) #:nodoc:
      return self unless p_addr

      Class.new(self) {
        @is_proxy_class = true

        if p_addr == :ENV then
          @proxy_from_env = true
          @proxy_address = nil
          @proxy_port    = nil
        else
          @proxy_from_env = false
          @proxy_address = p_addr
          @proxy_port    = p_port || default_port
        end

        @proxy_user = p_user
        @proxy_pass = p_pass
      }
    end

    class << HTTP
      # Returns true if self is a class which was created by HTTP::Proxy.
      def proxy_class?
        defined?(@is_proxy_class) ? @is_proxy_class : false
      end

      # Returns the address of the proxy host, or +nil+ if none;
      # see Gem::Net::HTTP@Proxy+Server.
      attr_reader :proxy_address

      # Returns the port number of the proxy host, or +nil+ if none;
      # see Gem::Net::HTTP@Proxy+Server.
      attr_reader :proxy_port

      # Returns the user name for accessing the proxy, or +nil+ if none;
      # see Gem::Net::HTTP@Proxy+Server.
      attr_reader :proxy_user

      # Returns the password for accessing the proxy, or +nil+ if none;
      # see Gem::Net::HTTP@Proxy+Server.
      attr_reader :proxy_pass
    end

    # Returns +true+ if a proxy server is defined, +false+ otherwise;
    # see {Proxy Server}[rdoc-ref:Gem::Net::HTTP@Proxy+Server].
    def proxy?
      !!(@proxy_from_env ? proxy_uri : @proxy_address)
    end

    # Returns +true+ if the proxy server is defined in the environment,
    # +false+ otherwise;
    # see {Proxy Server}[rdoc-ref:Gem::Net::HTTP@Proxy+Server].
    def proxy_from_env?
      @proxy_from_env
    end

    # The proxy URI determined from the environment for this connection.
    def proxy_uri # :nodoc:
      return if @proxy_uri == false
      @proxy_uri ||= Gem::URI::HTTP.new(
        "http", nil, address, port, nil, nil, nil, nil, nil
      ).find_proxy || false
      @proxy_uri || nil
    end

    # Returns the address of the proxy server, if defined, +nil+ otherwise;
    # see {Proxy Server}[rdoc-ref:Gem::Net::HTTP@Proxy+Server].
    def proxy_address
      if @proxy_from_env then
        proxy_uri&.hostname
      else
        @proxy_address
      end
    end

    # Returns the port number of the proxy server, if defined, +nil+ otherwise;
    # see {Proxy Server}[rdoc-ref:Gem::Net::HTTP@Proxy+Server].
    def proxy_port
      if @proxy_from_env then
        proxy_uri&.port
      else
        @proxy_port
      end
    end

    # Returns the user name of the proxy server, if defined, +nil+ otherwise;
    # see {Proxy Server}[rdoc-ref:Gem::Net::HTTP@Proxy+Server].
    def proxy_user
      if @proxy_from_env
        user = proxy_uri&.user
        unescape(user) if user
      else
        @proxy_user
      end
    end

    # Returns the password of the proxy server, if defined, +nil+ otherwise;
    # see {Proxy Server}[rdoc-ref:Gem::Net::HTTP@Proxy+Server].
    def proxy_pass
      if @proxy_from_env
        pass = proxy_uri&.password
        unescape(pass) if pass
      else
        @proxy_pass
      end
    end

    alias proxyaddr proxy_address   #:nodoc: obsolete
    alias proxyport proxy_port      #:nodoc: obsolete

    private

    def unescape(value)
      require 'cgi/util'
      CGI.unescape(value)
    end

    # without proxy, obsolete

    def conn_address # :nodoc:
      @ipaddr || address()
    end

    def conn_port # :nodoc:
      port()
    end

    def edit_path(path)
      if proxy?
        if path.start_with?("ftp://") || use_ssl?
          path
        else
          "http://#{addr_port}#{path}"
        end
      else
        path
      end
    end

    #
    # HTTP operations
    #

    public

    # :call-seq:
    #    get(path, initheader = nil) {|res| ... }
    #
    # Sends a GET request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Get object
    # created from string +path+ and initial headers hash +initheader+.
    #
    # With a block given, calls the block with the response body:
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.get('/todos/1') do |res|
    #     p res
    #   end # => #<Gem::Net::HTTPOK 200 OK readbody=true>
    #
    # Output:
    #
    #   "{\n  \"userId\": 1,\n  \"id\": 1,\n  \"title\": \"delectus aut autem\",\n  \"completed\": false\n}"
    #
    # With no block given, simply returns the response object:
    #
    #   http.get('/') # => #<Gem::Net::HTTPOK 200 OK readbody=true>
    #
    # Related:
    #
    # - Gem::Net::HTTP::Get: request class for \HTTP method GET.
    # - Gem::Net::HTTP.get: sends GET request, returns response body.
    #
    def get(path, initheader = nil, dest = nil, &block) # :yield: +body_segment+
      res = nil

      request(Get.new(path, initheader)) {|r|
        r.read_body dest, &block
        res = r
      }
      res
    end

    # Sends a HEAD request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Head object
    # created from string +path+ and initial headers hash +initheader+:
    #
    #   res = http.head('/todos/1') # => #<Gem::Net::HTTPOK 200 OK readbody=true>
    #   res.body                    # => nil
    #   res.to_hash.take(3)
    #   # =>
    #   [["date", ["Wed, 15 Feb 2023 15:25:42 GMT"]],
    #    ["content-type", ["application/json; charset=utf-8"]],
    #    ["connection", ["close"]]]
    #
    def head(path, initheader = nil)
      request(Head.new(path, initheader))
    end

    # :call-seq:
    #    post(path, data, initheader = nil) {|res| ... }
    #
    # Sends a POST request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Post object
    # created from string +path+, string +data+, and initial headers hash +initheader+.
    #
    # With a block given, calls the block with the response body:
    #
    #   data = '{"userId": 1, "id": 1, "title": "delectus aut autem", "completed": false}'
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.post('/todos', data) do |res|
    #     p res
    #   end # => #<Gem::Net::HTTPCreated 201 Created readbody=true>
    #
    # Output:
    #
    #   "{\n  \"{\\\"userId\\\": 1, \\\"id\\\": 1, \\\"title\\\": \\\"delectus aut autem\\\", \\\"completed\\\": false}\": \"\",\n  \"id\": 201\n}"
    #
    # With no block given, simply returns the response object:
    #
    #   http.post('/todos', data) # => #<Gem::Net::HTTPCreated 201 Created readbody=true>
    #
    # Related:
    #
    # - Gem::Net::HTTP::Post: request class for \HTTP method POST.
    # - Gem::Net::HTTP.post: sends POST request, returns response body.
    #
    def post(path, data, initheader = nil, dest = nil, &block) # :yield: +body_segment+
      send_entity(path, data, initheader, dest, Post, &block)
    end

    # :call-seq:
    #    patch(path, data, initheader = nil) {|res| ... }
    #
    # Sends a PATCH request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Patch object
    # created from string +path+, string +data+, and initial headers hash +initheader+.
    #
    # With a block given, calls the block with the response body:
    #
    #   data = '{"userId": 1, "id": 1, "title": "delectus aut autem", "completed": false}'
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.patch('/todos/1', data) do |res|
    #     p res
    #   end # => #<Gem::Net::HTTPOK 200 OK readbody=true>
    #
    # Output:
    #
    #   "{\n  \"userId\": 1,\n  \"id\": 1,\n  \"title\": \"delectus aut autem\",\n  \"completed\": false,\n  \"{\\\"userId\\\": 1, \\\"id\\\": 1, \\\"title\\\": \\\"delectus aut autem\\\", \\\"completed\\\": false}\": \"\"\n}"
    #
    # With no block given, simply returns the response object:
    #
    #   http.patch('/todos/1', data) # => #<Gem::Net::HTTPCreated 201 Created readbody=true>
    #
    def patch(path, data, initheader = nil, dest = nil, &block) # :yield: +body_segment+
      send_entity(path, data, initheader, dest, Patch, &block)
    end

    # Sends a PUT request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Put object
    # created from string +path+, string +data+, and initial headers hash +initheader+.
    #
    #   data = '{"userId": 1, "id": 1, "title": "delectus aut autem", "completed": false}'
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.put('/todos/1', data) # => #<Gem::Net::HTTPOK 200 OK readbody=true>
    #
    def put(path, data, initheader = nil)
      request(Put.new(path, initheader), data)
    end

    # Sends a PROPPATCH request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Proppatch object
    # created from string +path+, string +body+, and initial headers hash +initheader+.
    #
    #   data = '{"userId": 1, "id": 1, "title": "delectus aut autem", "completed": false}'
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.proppatch('/todos/1', data)
    #
    def proppatch(path, body, initheader = nil)
      request(Proppatch.new(path, initheader), body)
    end

    # Sends a LOCK request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Lock object
    # created from string +path+, string +body+, and initial headers hash +initheader+.
    #
    #   data = '{"userId": 1, "id": 1, "title": "delectus aut autem", "completed": false}'
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.lock('/todos/1', data)
    #
    def lock(path, body, initheader = nil)
      request(Lock.new(path, initheader), body)
    end

    # Sends an UNLOCK request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Unlock object
    # created from string +path+, string +body+, and initial headers hash +initheader+.
    #
    #   data = '{"userId": 1, "id": 1, "title": "delectus aut autem", "completed": false}'
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.unlock('/todos/1', data)
    #
    def unlock(path, body, initheader = nil)
      request(Unlock.new(path, initheader), body)
    end

    # Sends an Options request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Options object
    # created from string +path+ and initial headers hash +initheader+.
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.options('/')
    #
    def options(path, initheader = nil)
      request(Options.new(path, initheader))
    end

    # Sends a PROPFIND request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Propfind object
    # created from string +path+, string +body+, and initial headers hash +initheader+.
    #
    #   data = '{"userId": 1, "id": 1, "title": "delectus aut autem", "completed": false}'
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.propfind('/todos/1', data)
    #
    def propfind(path, body = nil, initheader = {'Depth' => '0'})
      request(Propfind.new(path, initheader), body)
    end

    # Sends a DELETE request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Delete object
    # created from string +path+ and initial headers hash +initheader+.
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.delete('/todos/1')
    #
    def delete(path, initheader = {'Depth' => 'Infinity'})
      request(Delete.new(path, initheader))
    end

    # Sends a MOVE request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Move object
    # created from string +path+ and initial headers hash +initheader+.
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.move('/todos/1')
    #
    def move(path, initheader = nil)
      request(Move.new(path, initheader))
    end

    # Sends a COPY request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Copy object
    # created from string +path+ and initial headers hash +initheader+.
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.copy('/todos/1')
    #
    def copy(path, initheader = nil)
      request(Copy.new(path, initheader))
    end

    # Sends a MKCOL request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Mkcol object
    # created from string +path+, string +body+, and initial headers hash +initheader+.
    #
    #   data = '{"userId": 1, "id": 1, "title": "delectus aut autem", "completed": false}'
    #   http.mkcol('/todos/1', data)
    #   http = Gem::Net::HTTP.new(hostname)
    #
    def mkcol(path, body = nil, initheader = nil)
      request(Mkcol.new(path, initheader), body)
    end

    # Sends a TRACE request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Trace object
    # created from string +path+ and initial headers hash +initheader+.
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.trace('/todos/1')
    #
    def trace(path, initheader = nil)
      request(Trace.new(path, initheader))
    end

    # Sends a GET request to the server;
    # forms the response into a Gem::Net::HTTPResponse object.
    #
    # The request is based on the Gem::Net::HTTP::Get object
    # created from string +path+ and initial headers hash +initheader+.
    #
    # With no block given, returns the response object:
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.request_get('/todos') # => #<Gem::Net::HTTPOK 200 OK readbody=true>
    #
    # With a block given, calls the block with the response object
    # and returns the response object:
    #
    #   http.request_get('/todos') do |res|
    #     p res
    #   end # => #<Gem::Net::HTTPOK 200 OK readbody=true>
    #
    # Output:
    #
    #   #<Gem::Net::HTTPOK 200 OK readbody=false>
    #
    def request_get(path, initheader = nil, &block) # :yield: +response+
      request(Get.new(path, initheader), &block)
    end

    # Sends a HEAD request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Head object
    # created from string +path+ and initial headers hash +initheader+.
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.head('/todos/1') # => #<Gem::Net::HTTPOK 200 OK readbody=true>
    #
    def request_head(path, initheader = nil, &block)
      request(Head.new(path, initheader), &block)
    end

    # Sends a POST request to the server;
    # forms the response into a Gem::Net::HTTPResponse object.
    #
    # The request is based on the Gem::Net::HTTP::Post object
    # created from string +path+, string +data+, and initial headers hash +initheader+.
    #
    # With no block given, returns the response object:
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.post('/todos', 'xyzzy')
    #   # => #<Gem::Net::HTTPCreated 201 Created readbody=true>
    #
    # With a block given, calls the block with the response body
    # and returns the response object:
    #
    #   http.post('/todos', 'xyzzy') do |res|
    #     p res
    #   end # => #<Gem::Net::HTTPCreated 201 Created readbody=true>
    #
    # Output:
    #
    #   "{\n  \"xyzzy\": \"\",\n  \"id\": 201\n}"
    #
    def request_post(path, data, initheader = nil, &block) # :yield: +response+
      request Post.new(path, initheader), data, &block
    end

    # Sends a PUT request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTP::Put object
    # created from string +path+, string +data+, and initial headers hash +initheader+.
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.put('/todos/1', 'xyzzy')
    #   # => #<Gem::Net::HTTPOK 200 OK readbody=true>
    #
    def request_put(path, data, initheader = nil, &block)   #:nodoc:
      request Put.new(path, initheader), data, &block
    end

    alias get2   request_get    #:nodoc: obsolete
    alias head2  request_head   #:nodoc: obsolete
    alias post2  request_post   #:nodoc: obsolete
    alias put2   request_put    #:nodoc: obsolete

    # Sends an \HTTP request to the server;
    # returns an instance of a subclass of Gem::Net::HTTPResponse.
    #
    # The request is based on the Gem::Net::HTTPRequest object
    # created from string +path+, string +data+, and initial headers hash +header+.
    # That object is an instance of the
    # {subclass of Gem::Net::HTTPRequest}[rdoc-ref:Gem::Net::HTTPRequest@Request+Subclasses],
    # that corresponds to the given uppercase string +name+,
    # which must be
    # an {HTTP request method}[https://en.wikipedia.org/wiki/HTTP#Request_methods]
    # or a {WebDAV request method}[https://en.wikipedia.org/wiki/WebDAV#Implementation].
    #
    # Examples:
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #   http.send_request('GET', '/todos/1')
    #   # => #<Gem::Net::HTTPOK 200 OK readbody=true>
    #   http.send_request('POST', '/todos', 'xyzzy')
    #   # => #<Gem::Net::HTTPCreated 201 Created readbody=true>
    #
    def send_request(name, path, data = nil, header = nil)
      has_response_body = name != 'HEAD'
      r = HTTPGenericRequest.new(name,(data ? true : false),has_response_body,path,header)
      request r, data
    end

    # Sends the given request +req+ to the server;
    # forms the response into a Gem::Net::HTTPResponse object.
    #
    # The given +req+ must be an instance of a
    # {subclass of Gem::Net::HTTPRequest}[rdoc-ref:Gem::Net::HTTPRequest@Request+Subclasses].
    # Argument +body+ should be given only if needed for the request.
    #
    # With no block given, returns the response object:
    #
    #   http = Gem::Net::HTTP.new(hostname)
    #
    #   req = Gem::Net::HTTP::Get.new('/todos/1')
    #   http.request(req)
    #   # => #<Gem::Net::HTTPOK 200 OK readbody=true>
    #
    #   req = Gem::Net::HTTP::Post.new('/todos')
    #   http.request(req, 'xyzzy')
    #   # => #<Gem::Net::HTTPCreated 201 Created readbody=true>
    #
    # With a block given, calls the block with the response and returns the response:
    #
    #   req = Gem::Net::HTTP::Get.new('/todos/1')
    #   http.request(req) do |res|
    #     p res
    #   end # => #<Gem::Net::HTTPOK 200 OK readbody=true>
    #
    # Output:
    #
    #   #<Gem::Net::HTTPOK 200 OK readbody=false>
    #
    def request(req, body = nil, &block)  # :yield: +response+
      unless started?
        start {
          req['connection'] ||= 'close'
          return request(req, body, &block)
        }
      end
      if proxy_user()
        req.proxy_basic_auth proxy_user(), proxy_pass() unless use_ssl?
      end
      req.set_body_internal body
      res = transport_request(req, &block)
      if sspi_auth?(res)
        sspi_auth(req)
        res = transport_request(req, &block)
      end
      res
    end

    private

    # Executes a request which uses a representation
    # and returns its body.
    def send_entity(path, data, initheader, dest, type, &block)
      res = nil
      request(type.new(path, initheader), data) {|r|
        r.read_body dest, &block
        res = r
      }
      res
    end

    IDEMPOTENT_METHODS_ = %w/GET HEAD PUT DELETE OPTIONS TRACE/ # :nodoc:

    def transport_request(req)
      count = 0
      begin
        begin_transport req
        res = catch(:response) {
          begin
            req.exec @socket, @curr_http_version, edit_path(req.path)
          rescue Errno::EPIPE
            # Failure when writing full request, but we can probably
            # still read the received response.
          end

          begin
            res = HTTPResponse.read_new(@socket)
            res.decode_content = req.decode_content
            res.body_encoding = @response_body_encoding
            res.ignore_eof = @ignore_eof
          end while res.kind_of?(HTTPInformation)

          res.uri = req.uri

          res
        }
        res.reading_body(@socket, req.response_body_permitted?) {
          yield res if block_given?
        }
      rescue Gem::Net::OpenTimeout
        raise
      rescue Gem::Net::ReadTimeout, IOError, EOFError,
             Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EPIPE, Errno::ETIMEDOUT,
             # avoid a dependency on OpenSSL
             defined?(OpenSSL::SSL) ? OpenSSL::SSL::SSLError : IOError,
             Gem::Timeout::Error => exception
        if count < max_retries && IDEMPOTENT_METHODS_.include?(req.method)
          count += 1
          @socket.close if @socket
          debug "Conn close because of error #{exception}, and retry"
          retry
        end
        debug "Conn close because of error #{exception}"
        @socket.close if @socket
        raise
      end

      end_transport req, res
      res
    rescue => exception
      debug "Conn close because of error #{exception}"
      @socket.close if @socket
      raise exception
    end

    def begin_transport(req)
      if @socket.closed?
        connect
      elsif @last_communicated
        if @last_communicated + @keep_alive_timeout < Process.clock_gettime(Process::CLOCK_MONOTONIC)
          debug 'Conn close because of keep_alive_timeout'
          @socket.close
          connect
        elsif @socket.io.to_io.wait_readable(0) && @socket.eof?
          debug "Conn close because of EOF"
          @socket.close
          connect
        end
      end

      if not req.response_body_permitted? and @close_on_empty_response
        req['connection'] ||= 'close'
      end

      req.update_uri address, port, use_ssl?
      req['host'] ||= addr_port()
    end

    def end_transport(req, res)
      @curr_http_version = res.http_version
      @last_communicated = nil
      if @socket.closed?
        debug 'Conn socket closed'
      elsif not res.body and @close_on_empty_response
        debug 'Conn close'
        @socket.close
      elsif keep_alive?(req, res)
        debug 'Conn keep-alive'
        @last_communicated = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      else
        debug 'Conn close'
        @socket.close
      end
    end

    def keep_alive?(req, res)
      return false if req.connection_close?
      if @curr_http_version <= '1.0'
        res.connection_keep_alive?
      else   # HTTP/1.1 or later
        not res.connection_close?
      end
    end

    def sspi_auth?(res)
      return false unless @sspi_enabled
      if res.kind_of?(HTTPProxyAuthenticationRequired) and
          proxy? and res["Proxy-Authenticate"].include?("Negotiate")
        begin
          require 'win32/sspi'
          true
        rescue LoadError
          false
        end
      else
        false
      end
    end

    def sspi_auth(req)
      n = Win32::SSPI::NegotiateAuth.new
      req["Proxy-Authorization"] = "Negotiate #{n.get_initial_token}"
      # Some versions of ISA will close the connection if this isn't present.
      req["Connection"] = "Keep-Alive"
      req["Proxy-Connection"] = "Keep-Alive"
      res = transport_request(req)
      authphrase = res["Proxy-Authenticate"]  or return res
      req["Proxy-Authorization"] = "Negotiate #{n.complete_authentication(authphrase)}"
    rescue => err
      raise HTTPAuthenticationError.new('HTTP authentication failed', err)
    end

    #
    # utils
    #

    private

    def addr_port
      addr = address
      addr = "[#{addr}]" if addr.include?(":")
      default_port = use_ssl? ? HTTP.https_default_port : HTTP.http_default_port
      default_port == port ? addr : "#{addr}:#{port}"
    end

    # Adds a message to debugging output
    def debug(msg)
      return unless @debug_output
      @debug_output << msg
      @debug_output << "\n"
    end

    alias_method :D, :debug
  end

end

require_relative 'http/exceptions'

require_relative 'http/header'

require_relative 'http/generic_request'
require_relative 'http/request'
require_relative 'http/requests'

require_relative 'http/response'
require_relative 'http/responses'

require_relative 'http/proxy_delta'

require_relative 'http/backward'
