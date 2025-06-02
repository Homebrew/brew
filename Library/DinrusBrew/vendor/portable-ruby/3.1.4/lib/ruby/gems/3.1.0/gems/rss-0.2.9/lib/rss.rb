# frozen_string_literal: false
##
# = RSS reading and writing
#
# Really Simple Syndication (RSS) is a family of formats that describe 'feeds,'
# specially constructed XML documents that allow an interested person to
# subscribe and receive updates from a particular web service. This portion of
# the standard library provides tooling to read and create these feeds.
#
# The standard library supports RSS 0.91, 1.0, 2.0, and Atom, a related format.
# Here are some links to the standards documents for these formats:
#
# * RSS
#   * 0.9.1[http://www.rssboard.org/rss-0-9-1-netscape]
#   * 1.0[http://web.resource.org/rss/1.0/]
#   * 2.0[http://www.rssboard.org/rss-specification]
# * Atom[http://tools.ietf.org/html/rfc4287]
#
# == Consuming RSS
#
# If you'd like to read someone's RSS feed with your Ruby code, you've come to
# the right place. It's really easy to do this, but we'll need the help of
# open-uri:
#
#   require 'rss'
#   require 'open-uri'
#
#   url = 'http://www.ruby-lang.org/en/feeds/news.rss'
#   open(url) do |rss|
#     feed = RSS::Parser.parse(rss)
#     puts "Title: #{feed.channel.title}"
#     feed.items.each do |item|
#       puts "Item: #{item.title}"
#     end
#   end
#
# As you can see, the workhorse is RSS::Parser#parse, which takes the source of
# the feed and a parameter that performs validation on the feed. We get back an
# object that has all of the data from our feed, accessible through methods.
# This example shows getting the title out of the channel element, and looping
# through the list of items.
#
# == Producing RSS
#
# Producing our own RSS feeds is easy as well. Let's make a very basic feed:
#
#   require "rss"
#
#   rss = RSS::Maker.make("atom") do |maker|
#     maker.channel.author = "matz"
#     maker.channel.updated = Time.now.to_s
#     maker.channel.about = "http://www.ruby-lang.org/en/feeds/news.rss"
#     maker.channel.title = "Example Feed"
#
#     maker.items.new_item do |item|
#       item.link = "http://www.ruby-lang.org/en/news/2010/12/25/ruby-1-9-2-p136-is-released/"
#       item.title = "Ruby 1.9.2-p136 is released"
#       item.updated = Time.now.to_s
#     end
#   end
#
#   puts rss
#
# As you can see, this is a very Builder-like DSL. This code will spit out an
# Atom feed with one item. If we needed a second item, we'd make another block
# with maker.items.new_item and build a second one.
#
# == Copyright
#
# Copyright (c) 2003-2007 Kouhei Sutou <kou@cozmixng.org>
#
# You can redistribute it and/or modify it under the same terms as Ruby.
#
# There is an additional tutorial by the author of RSS at:
# http://www.cozmixng.org/~rwiki/?cmd=view;name=RSS+Parser%3A%3ATutorial.en

module RSS
end

require "rss/version"

require 'rss/1.0'
require 'rss/2.0'
require 'rss/atom'
require 'rss/content'
require 'rss/dublincore'
require 'rss/image'
require 'rss/itunes'
require 'rss/slash'
require 'rss/syndication'
require 'rss/taxonomy'
require 'rss/trackback'

require "rss/maker"
