# frozen_string_literal: true

# HTTP/1.1 methods --- RFC2616

# \Class for representing
# {HTTP method GET}[https://en.wikipedia.org/w/index.php?title=Hypertext_Transfer_Protocol#GET_method]:
#
#   require 'net/http'
#   uri = URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Net::HTTP::Get.new(uri) # => #<Net::HTTP::Get GET>
#   res = Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Net::HTTPRequest@Request+Headers].
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
# - Net::HTTP.get: sends +GET+ request, returns response body.
# - Net::HTTP#get: sends +GET+ request, returns response object.
#
class Net::HTTP::Get < Net::HTTPRequest
  METHOD = 'GET'
  REQUEST_HAS_BODY  = false
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {HTTP method HEAD}[https://en.wikipedia.org/w/index.php?title=Hypertext_Transfer_Protocol#HEAD_method]:
#
#   require 'net/http'
#   uri = URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Net::HTTP::Head.new(uri) # => #<Net::HTTP::Head HEAD>
#   res = Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Net::HTTPRequest@Request+Headers].
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
# - Net::HTTP#head: sends +HEAD+ request, returns response object.
#
class Net::HTTP::Head < Net::HTTPRequest
  METHOD = 'HEAD'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = false
end

# \Class for representing
# {HTTP method POST}[https://en.wikipedia.org/w/index.php?title=Hypertext_Transfer_Protocol#POST_method]:
#
#   require 'net/http'
#   uri = URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   uri.path = '/posts'
#   req = Net::HTTP::Post.new(uri) # => #<Net::HTTP::Post POST>
#   req.body = '{"title": "foo","body": "bar","userId": 1}'
#   req.content_type = 'application/json'
#   res = Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Net::HTTPRequest@Request+Headers].
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
# - Net::HTTP.post: sends +POST+ request, returns response object.
# - Net::HTTP#post: sends +POST+ request, returns response object.
#
class Net::HTTP::Post < Net::HTTPRequest
  METHOD = 'POST'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {HTTP method PUT}[https://en.wikipedia.org/w/index.php?title=Hypertext_Transfer_Protocol#PUT_method]:
#
#   require 'net/http'
#   uri = URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   uri.path = '/posts'
#   req = Net::HTTP::Put.new(uri) # => #<Net::HTTP::Put PUT>
#   req.body = '{"title": "foo","body": "bar","userId": 1}'
#   req.content_type = 'application/json'
#   res = Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Net::HTTPRequest@Request+Headers].
#
# Properties:
#
# - Request body: yes.
# - Response body: yes.
# - {Safe}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Safe_methods]: no.
# - {Idempotent}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Idempotent_methods]: yes.
# - {Cacheable}[https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol#Cacheable_methods]: no.
#
class Net::HTTP::Put < Net::HTTPRequest
  METHOD = 'PUT'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {HTTP method DELETE}[https://en.wikipedia.org/w/index.php?title=Hypertext_Transfer_Protocol#DELETE_method]:
#
#   require 'net/http'
#   uri = URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   uri.path = '/posts/1'
#   req = Net::HTTP::Delete.new(uri) # => #<Net::HTTP::Delete DELETE>
#   res = Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Net::HTTPRequest@Request+Headers].
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
# - Net::HTTP#delete: sends +DELETE+ request, returns response object.
#
class Net::HTTP::Delete < Net::HTTPRequest
  METHOD = 'DELETE'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {HTTP method OPTIONS}[https://en.wikipedia.org/w/index.php?title=Hypertext_Transfer_Protocol#OPTIONS_method]:
#
#   require 'net/http'
#   uri = URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Net::HTTP::Options.new(uri) # => #<Net::HTTP::Options OPTIONS>
#   res = Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Net::HTTPRequest@Request+Headers].
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
# - Net::HTTP#options: sends +OPTIONS+ request, returns response object.
#
class Net::HTTP::Options < Net::HTTPRequest
  METHOD = 'OPTIONS'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {HTTP method TRACE}[https://en.wikipedia.org/w/index.php?title=Hypertext_Transfer_Protocol#TRACE_method]:
#
#   require 'net/http'
#   uri = URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Net::HTTP::Trace.new(uri) # => #<Net::HTTP::Trace TRACE>
#   res = Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Net::HTTPRequest@Request+Headers].
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
# - Net::HTTP#trace: sends +TRACE+ request, returns response object.
#
class Net::HTTP::Trace < Net::HTTPRequest
  METHOD = 'TRACE'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {HTTP method PATCH}[https://en.wikipedia.org/w/index.php?title=Hypertext_Transfer_Protocol#PATCH_method]:
#
#   require 'net/http'
#   uri = URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   uri.path = '/posts'
#   req = Net::HTTP::Patch.new(uri) # => #<Net::HTTP::Patch PATCH>
#   req.body = '{"title": "foo","body": "bar","userId": 1}'
#   req.content_type = 'application/json'
#   res = Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Net::HTTPRequest@Request+Headers].
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
# - Net::HTTP#patch: sends +PATCH+ request, returns response object.
#
class Net::HTTP::Patch < Net::HTTPRequest
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
#   require 'net/http'
#   uri = URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Net::HTTP::Propfind.new(uri) # => #<Net::HTTP::Propfind PROPFIND>
#   res = Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Net::HTTPRequest@Request+Headers].
#
# Related:
#
# - Net::HTTP#propfind: sends +PROPFIND+ request, returns response object.
#
class Net::HTTP::Propfind < Net::HTTPRequest
  METHOD = 'PROPFIND'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {WebDAV method PROPPATCH}[http://www.webdav.org/specs/rfc4918.html#METHOD_PROPPATCH]:
#
#   require 'net/http'
#   uri = URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Net::HTTP::Proppatch.new(uri) # => #<Net::HTTP::Proppatch PROPPATCH>
#   res = Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Net::HTTPRequest@Request+Headers].
#
# Related:
#
# - Net::HTTP#proppatch: sends +PROPPATCH+ request, returns response object.
#
class Net::HTTP::Proppatch < Net::HTTPRequest
  METHOD = 'PROPPATCH'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {WebDAV method MKCOL}[http://www.webdav.org/specs/rfc4918.html#METHOD_MKCOL]:
#
#   require 'net/http'
#   uri = URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Net::HTTP::Mkcol.new(uri) # => #<Net::HTTP::Mkcol MKCOL>
#   res = Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Net::HTTPRequest@Request+Headers].
#
# Related:
#
# - Net::HTTP#mkcol: sends +MKCOL+ request, returns response object.
#
class Net::HTTP::Mkcol < Net::HTTPRequest
  METHOD = 'MKCOL'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {WebDAV method COPY}[http://www.webdav.org/specs/rfc4918.html#METHOD_COPY]:
#
#   require 'net/http'
#   uri = URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Net::HTTP::Copy.new(uri) # => #<Net::HTTP::Copy COPY>
#   res = Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Net::HTTPRequest@Request+Headers].
#
# Related:
#
# - Net::HTTP#copy: sends +COPY+ request, returns response object.
#
class Net::HTTP::Copy < Net::HTTPRequest
  METHOD = 'COPY'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {WebDAV method MOVE}[http://www.webdav.org/specs/rfc4918.html#METHOD_MOVE]:
#
#   require 'net/http'
#   uri = URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Net::HTTP::Move.new(uri) # => #<Net::HTTP::Move MOVE>
#   res = Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Net::HTTPRequest@Request+Headers].
#
# Related:
#
# - Net::HTTP#move: sends +MOVE+ request, returns response object.
#
class Net::HTTP::Move < Net::HTTPRequest
  METHOD = 'MOVE'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {WebDAV method LOCK}[http://www.webdav.org/specs/rfc4918.html#METHOD_LOCK]:
#
#   require 'net/http'
#   uri = URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Net::HTTP::Lock.new(uri) # => #<Net::HTTP::Lock LOCK>
#   res = Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Net::HTTPRequest@Request+Headers].
#
# Related:
#
# - Net::HTTP#lock: sends +LOCK+ request, returns response object.
#
class Net::HTTP::Lock < Net::HTTPRequest
  METHOD = 'LOCK'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# \Class for representing
# {WebDAV method UNLOCK}[http://www.webdav.org/specs/rfc4918.html#METHOD_UNLOCK]:
#
#   require 'net/http'
#   uri = URI('http://example.com')
#   hostname = uri.hostname # => "example.com"
#   req = Net::HTTP::Unlock.new(uri) # => #<Net::HTTP::Unlock UNLOCK>
#   res = Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end
#
# See {Request Headers}[rdoc-ref:Net::HTTPRequest@Request+Headers].
#
# Related:
#
# - Net::HTTP#unlock: sends +UNLOCK+ request, returns response object.
#
class Net::HTTP::Unlock < Net::HTTPRequest
  METHOD = 'UNLOCK'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

