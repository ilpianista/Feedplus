#!/usr/bin/env ruby
# MIT License
#
# Copyright (c) 2017 Andrea Scarpino <me@andreascarpino.it>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE

require 'net/http'
require 'json'
require 'optparse'
require 'ostruct'
require 'rss'

$options = OpenStruct.new
$options.id = ""
$options.hashtags = []
$options.limit = 20
$options.feedTitle = "Your feed title"
$options.feedUrl = "http://your.domain.com/"

def getPosts(pageToken = "nextPageToken")
  uri = URI("https://www.googleapis.com/plus/v1/people/#{$options.id}/activities/public")
  params = { :fields => 'items(actor/displayName,annotation,object(actor/displayName,attachments(content,displayName,fullImage/url,objectType,url),content),published,title,updated,url,verb),nextPageToken',
             :key => 'AIzaSyDjcCZGSGTIaMA3VXmEjATkTlX4iRAoPiM',
             :maxResults => 100,
             :pageToken => pageToken }
  uri.query = URI.encode_www_form(params)

  res = Net::HTTP.get_response(uri)
  if res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  else
    puts "Something went wrong :-("
    exit
  end
end

def parse(args)
  opt_parser = OptionParser.new do |opts|
    opts.banner = "Usage: feedplus.rb [options]"
    opts.separator ""
    opts.separator "Options:"

    opts.on("--id <id>", "--user <id>", "Google+ user ID") do |id|
      $options.id = id
    end

    opts.on("-f", "--filter <tag1, tag2, ...>", Array, "Fetch only posts having these hashtags") do |tags|
      $options.hashtags = tags.map{|t| t.downcase}
    end

    opts.on("-l", "--limit <n>", Integer, "Fetch at most N posts per feed (default: 20)") do |limit|
      $options.limit = limit
    end

    opts.on("-t", "--title <title>", "Feed title") do |title|
      $options.feedTitle = title
    end

    opts.on("-u", "--url <url>", "Feed URL") do |url|
      $options.feedUrl = url
    end

    opts.on_tail("-h", "--help", "Show this help") do
      puts opts
      exit
    end
  end

  opt_parser.parse!(args)
end

def makeRSS
  rss = RSS::Maker.make("2.0") do |maker|
    channel = maker.channel
    channel.title = $options.feedTitle
    channel.description = channel.title
    channel.link = $options.feedUrl

    items = getPosts
    counter = 0

    catch :done do
      while counter < $options.limit
        items.fetch("items").each do |post|
          catch :none do
            $options.hashtags.each do |tag|
              throw :none unless post.fetch("object").fetch("content").downcase.include?("##{tag}")
            end

            addPost(maker, post)

            counter += 1
            throw :done if counter >= $options.limit
          end
        end

        if items.has_key?("nextPageToken")
          items = getPosts(items.fetch("nextPageToken"))
        else
          break
        end
      end
    end
  end

  rss
end

def addPost(maker, post)
  maker.items.new_item do |item|
    item.title = post.fetch("title")

    # Elide title when text is very long
    if item.title.length >= 40
      item.title = item.title[0, 37]
      item.title += '...'
    end

    item.link = post.fetch("url")

    item.description = ""
    if post.fetch("verb").eql?("share")
      if post.has_key?("annotation")
        item.description = post.fetch("annotation")
      end
    end
    item.description += post.fetch("object").fetch("content")
    item.pubDate = post.fetch("published")
    item.author = post.fetch("actor").fetch("displayName")

    if post.fetch("object").has_key?("attachments")
      item.description += "<br /><br />"

      attachments = post.fetch("object").fetch("attachments")
      if attachments.first.has_key?("fullImage")
        url = attachments.first.fetch("fullImage").fetch("url")
        item.description += "<a href='#{url}'><img src='#{url}'></a>"
      end

      if attachments.first.fetch("objectType").eql?("article")
        item.description += "<br /><br />"
        item.description += "<a href='#{attachments.first.fetch('url')}'>#{attachments.first.fetch('displayName')}</a>"
      end
    end
  end
end

parse(ARGV)

if $options.id.empty?
  puts "Please, specify a user ID (run with `-h` to get help)."
  exit
end

rss = makeRSS

puts rss unless rss.nil?
