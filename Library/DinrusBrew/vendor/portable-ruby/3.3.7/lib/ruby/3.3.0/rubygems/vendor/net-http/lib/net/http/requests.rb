# frozen_string_literal: true

# HTTP/1.1 methods --- RFC2616

# \Class for representing
# {HTTP method GET}[https://en.wikipedia.org/w/index.php?title=Hypertext_Transfer_Protocol#GET_method]:
#
#   require 'rubygems/vendor/net-http/lib/net/http'
#   uri = Gem::URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Gem::Net::HTTP::Get.new(uri) # => #<Gem::Net::HTTP::Get GET>
#   res = Gem::Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Gem::Net::HTTPRequest@Request+Headers].
#
# Properties:
#
# - Request body: optional.
# - Response body: yes.
# - {Safe}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Safe_methods]: yes.
# - {Idempotent}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Idempotent_methods]: yes.
# - {Cacheable}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Cacheable_methods]: yes.
#
# Related:
#
# - Gem::Net::HTTP.get: sends +GET+ request, returns response body.
# - Gem::Net::HTTP#get: sends +GET+ request, returns response object.
#
class Gem::Net::HTTP::Get < Gem::Net::HTTPRequest
  METHOD = 'GET'
  REQUEST_HAS_BODY  = false
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {HTTP method HEAD}[https://en.wikipedia.org/w/index.php?title=Hypertext_Transfer_Protocol#HEAD_method]:
#
#   require 'rubygems/vendor/net-http/lib/net/http'
#   uri = Gem::URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Gem::Net::HTTP::Head.new(uri) # => #<Gem::Net::HTTP::Head HEAD>
#   res = Gem::Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Gem::Net::HTTPRequest@Request+Headers].
#
# Properties:
#
# - Request body: optional.
# - Response body: no.
# - {Safe}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Safe_methods]: yes.
# - {Idempotent}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Idempotent_methods]: yes.
# - {Cacheable}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Cacheable_methods]: yes.
#
# Related:
#
# - Gem::Net::HTTP#head: sends +HEAD+ request, returns response object.
#
class Gem::Net::HTTP::Head < Gem::Net::HTTPRequest
  METHOD = 'HEAD'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = false
end

# \Class for representing
# {HTTP method POST}[https://en.wikipedia.org/w/index.php?title=Hypertext_Transfer_Protocol#POST_method]:
#
#   require 'rubygems/vendor/net-http/lib/net/http'
#   uri = Gem::URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   uri.path = '/posts'
#   req = Gem::Net::HTTP::Post.new(uri) # => #<Gem::Net::HTTP::Post POST>
#   req.body = '{"title": "foo","body": "bar","userId": 1}'
#   req.content_type = 'application/json'
#   res = Gem::Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Gem::Net::HTTPRequest@Request+Headers].
#
# Properties:
#
# - Request body: yes.
# - Response body: yes.
# - {Safe}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Safe_methods]: no.
# - {Idempotent}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Idempotent_methods]: no.
# - {Cacheable}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Cacheable_methods]: yes.
#
# Related:
#
# - Gem::Net::HTTP.post: sends +POST+ request, returns response object.
# - Gem::Net::HTTP#post: sends +POST+ request, returns response object.
#
class Gem::Net::HTTP::Post < Gem::Net::HTTPRequest
  METHOD = 'POST'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {HTTP method PUT}[https://en.wikipedia.org/w/index.php?title=Hypertext_Transfer_Protocol#PUT_method]:
#
#   require 'rubygems/vendor/net-http/lib/net/http'
#   uri = Gem::URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   uri.path = '/posts'
#   req = Gem::Net::HTTP::Put.new(uri) # => #<Gem::Net::HTTP::Put PUT>
#   req.body = '{"title": "foo","body": "bar","userId": 1}'
#   req.content_type = 'application/json'
#   res = Gem::Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Gem::Net::HTTPRequest@Request+Headers].
#
# Properties:
#
# - Request body: yes.
# - Response body: yes.
# - {Safe}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Safe_methods]: no.
# - {Idempotent}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Idempotent_methods]: yes.
# - {Cacheable}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Cacheable_methods]: no.
#
class Gem::Net::HTTP::Put < Gem::Net::HTTPRequest
  METHOD = 'PUT'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {HTTP method DELETE}[https://en.wikipedia.org/w/index.php?title=Hypertext_Transfer_Protocol#DELETE_method]:
#
#   require 'rubygems/vendor/net-http/lib/net/http'
#   uri = Gem::URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   uri.path = '/posts/1'
#   req = Gem::Net::HTTP::Delete.new(uri) # => #<Gem::Net::HTTP::Delete DELETE>
#   res = Gem::Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Gem::Net::HTTPRequest@Request+Headers].
#
# Properties:
#
# - Request body: optional.
# - Response body: yes.
# - {Safe}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Safe_methods]: no.
# - {Idempotent}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Idempotent_methods]: yes.
# - {Cacheable}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Cacheable_methods]: no.
#
# Related:
#
# - Gem::Net::HTTP#delete: sends +DELETE+ request, returns response object.
#
class Gem::Net::HTTP::Delete < Gem::Net::HTTPRequest
  METHOD = 'DELETE'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {HTTP method OPTIONS}[https://en.wikipedia.org/w/index.php?title=Hypertext_Transfer_Protocol#OPTIONS_method]:
#
#   require 'rubygems/vendor/net-http/lib/net/http'
#   uri = Gem::URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Gem::Net::HTTP::Options.new(uri) # => #<Gem::Net::HTTP::Options OPTIONS>
#   res = Gem::Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Gem::Net::HTTPRequest@Request+Headers].
#
# Properties:
#
# - Request body: optional.
# - Response body: yes.
# - {Safe}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Safe_methods]: yes.
# - {Idempotent}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Idempotent_methods]: yes.
# - {Cacheable}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Cacheable_methods]: no.
#
# Related:
#
# - Gem::Net::HTTP#options: sends +OPTIONS+ request, returns response object.
#
class Gem::Net::HTTP::Options < Gem::Net::HTTPRequest
  METHOD = 'OPTIONS'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {HTTP method TRACE}[https://en.wikipedia.org/w/index.php?title=Hypertext_Transfer_Protocol#TRACE_method]:
#
#   require 'rubygems/vendor/net-http/lib/net/http'
#   uri = Gem::URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Gem::Net::HTTP::Trace.new(uri) # => #<Gem::Net::HTTP::Trace TRACE>
#   res = Gem::Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Gem::Net::HTTPRequest@Request+Headers].
#
# Properties:
#
# - Request body: no.
# - Response body: yes.
# - {Safe}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Safe_methods]: yes.
# - {Idempotent}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Idempotent_methods]: yes.
# - {Cacheable}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Cacheable_methods]: no.
#
# Related:
#
# - Gem::Net::HTTP#trace: sends +TRACE+ request, returns response object.
#
class Gem::Net::HTTP::Trace < Gem::Net::HTTPRequest
  METHOD = 'TRACE'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {HTTP method PATCH}[https://en.wikipedia.org/w/index.php?title=Hypertext_Transfer_Protocol#PATCH_method]:
#
#   require 'rubygems/vendor/net-http/lib/net/http'
#   uri = Gem::URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   uri.path = '/posts'
#   req = Gem::Net::HTTP::Patch.new(uri) # => #<Gem::Net::HTTP::Patch PATCH>
#   req.body = '{"title": "foo","body": "bar","userId": 1}'
#   req.content_type = 'application/json'
#   res = Gem::Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Gem::Net::HTTPRequest@Request+Headers].
#
# Properties:
#
# - Request body: yes.
# - Response body: yes.
# - {Safe}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Safe_methods]: no.
# - {Idempotent}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Idempotent_methods]: no.
# - {Cacheable}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Cacheable_methods]: no.
#
# Related:
#
# - Gem::Net::HTTP#patch: sends +PATCH+ request, returns response object.
#
class Gem::Net::HTTP::Patch < Gem::Net::HTTPRequest
  METHOD = 'PATCH'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

#
# WebDAV methods --- RFC2518
#

# \Class for representing
# {WebDAV method PROPFIND}[http://www.webdav.org/specs/rfc4918.html#METHOD_PROPFIND]:
#
#   require 'rubygems/vendor/net-http/lib/net/http'
#   uri = Gem::URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Gem::Net::HTTP::Propfind.new(uri) # => #<Gem::Net::HTTP::Propfind PROPFIND>
#   res = Gem::Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Gem::Net::HTTPRequest@Request+Headers].
#
# Related:
#
# - Gem::Net::HTTP#propfind: sends +PROPFIND+ request, returns response object.
#
class Gem::Net::HTTP::Propfind < Gem::Net::HTTPRequest
  METHOD = 'PROPFIND'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {WebDAV method PROPPATCH}[http://www.webdav.org/specs/rfc4918.html#METHOD_PROPPATCH]:
#
#   require 'rubygems/vendor/net-http/lib/net/http'
#   uri = Gem::URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Gem::Net::HTTP::Proppatch.new(uri) # => #<Gem::Net::HTTP::Proppatch PROPPATCH>
#   res = Gem::Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Gem::Net::HTTPRequest@Request+Headers].
#
# Related:
#
# - Gem::Net::HTTP#proppatch: sends +PROPPATCH+ request, returns response object.
#
class Gem::Net::HTTP::Proppatch < Gem::Net::HTTPRequest
  METHOD = 'PROPPATCH'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {WebDAV method MKCOL}[http://www.webdav.org/specs/rfc4918.html#METHOD_MKCOL]:
#
#   require 'rubygems/vendor/net-http/lib/net/http'
#   uri = Gem::URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Gem::Net::HTTP::Mkcol.new(uri) # => #<Gem::Net::HTTP::Mkcol MKCOL>
#   res = Gem::Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Gem::Net::HTTPRequest@Request+Headers].
#
# Related:
#
# - Gem::Net::HTTP#mkcol: sends +MKCOL+ request, returns response object.
#
class Gem::Net::HTTP::Mkcol < Gem::Net::HTTPRequest
  METHOD = 'MKCOL'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {WebDAV method COPY}[http://www.webdav.org/specs/rfc4918.html#METHOD_COPY]:
#
#   require 'rubygems/vendor/net-http/lib/net/http'
#   uri = Gem::URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Gem::Net::HTTP::Copy.new(uri) # => #<Gem::Net::HTTP::Copy COPY>
#   res = Gem::Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Gem::Net::HTTPRequest@Request+Headers].
#
# Related:
#
# - Gem::Net::HTTP#copy: sends +COPY+ request, returns response object.
#
class Gem::Net::HTTP::Copy < Gem::Net::HTTPRequest
  METHOD = 'COPY'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {WebDAV method MOVE}[http://www.webdav.org/specs/rfc4918.html#METHOD_MOVE]:
#
#   require 'rubygems/vendor/net-http/lib/net/http'
#   uri = Gem::URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Gem::Net::HTTP::Move.new(uri) # => #<Gem::Net::HTTP::Move MOVE>
#   res = Gem::Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Gem::Net::HTTPRequest@Request+Headers].
#
# Related:
#
# - Gem::Net::HTTP#move: sends +MOVE+ request, returns response object.
#
class Gem::Net::HTTP::Move < Gem::Net::HTTPRequest
  METHOD = 'MOVE'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {WebDAV method LOCK}[http://www.webdav.org/specs/rfc4918.html#METHOD_LOCK]:
#
#   require 'rubygems/vendor/net-http/lib/net/http'
#   uri = Gem::URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Gem::Net::HTTP::Lock.new(uri) # => #<Gem::Net::HTTP::Lock LOCK>
#   res = Gem::Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Gem::Net::HTTPRequest@Request+Headers].
#
# Related:
#
# - Gem::Net::HTTP#lock: sends +LOCK+ request, returns response object.
#
class Gem::Net::HTTP::Lock < Gem::Net::HTTPRequest
  METHOD = 'LOCK'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {WebDAV method UNLOCK}[http://www.webdav.org/specs/rfc4918.html#METHOD_UNLOCK]:
#
#   require 'rubygems/vendor/net-http/lib/net/http'
#   uri = Gem::URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Gem::Net::HTTP::Unlock.new(uri) # => #<Gem::Net::HTTP::Unlock UNLOCK>
#   res = Gem::Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Gem::Net::HTTPRequest@Request+Headers].
#
# Related:
#
# - Gem::Net::HTTP#unlock: sends +UNLOCK+ request, returns response object.
#
class Gem::Net::HTTP::Unlock < Gem::Net::HTTPRequest
  METHOD = 'UNLOCK'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

