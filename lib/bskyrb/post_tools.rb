require "uri"
require_relative "../atproto/requests"
require "xrpc"
# module Bskyrb
#   include Atmosfire

#   class Client
#     include RequestUtils
#     attr_reader :session

#     def initialize(session)
#       @session = session
#     end
#   end
# end

module Bskyrb
  module PostTools
    def create_facets(text)
      text = text.force_encoding('utf-16').force_encoding('utf-8')

      facets = []

      # Regex patterns
      mention_pattern = /(^|\s|\()(@)([a-zA-Z0-9.-]+)(\b)/
      link_pattern = URI.regexp
      # hashtag_pattern = /(?:^|\s)(#[^\d\s]\S*)(?=\s)?/
      # hashtag_pattern = /(?:^|\s|[[:punct:]])(#[^\d\s][\w\d]+)/
      hashtag_pattern = /(?:^|\W)(#\w+)(?=\W)?/

      # Find hashtags
      text.enum_for(:scan, hashtag_pattern).each do |m|
        index_start = Regexp.last_match.offset(0).first
        index_end = Regexp.last_match.offset(0).last - 1

        loop_modified = false

        loop do
          break unless text[index_start].match?(/\W/) && text[index_start] != '#'
          index_start += 1
          loop_modified = true
        end

        index_end += 1 if loop_modified

        tag = text[index_start..index_end].strip.sub(/^#/, '').sub(/\W+$/, '')

        next if tag.match?(/^\d+$/) # nothing but numbers

        facets.push(
          "$type" => "app.bsky.richtext.facet",
          "index" => {
            "byteStart" => index_start,
            "byteEnd" => index_end,
          },
          "features" => [
            {
              'tag' => tag,
              "$type" => 'app.bsky.richtext.facet#tag',
            },
          ],
        )
      end

      # Find mentions
      text.enum_for(:scan, mention_pattern).each do |m|
        index_start = Regexp.last_match.offset(0).first
        index_end = Regexp.last_match.offset(0).last
        did = resolve_handle(@pds, (m.join("").strip)[1..-1])["did"]
        unless did.nil?
          facets.push(
            "$type" => "app.bsky.richtext.facet",
            "index" => {
              "byteStart" => index_start,
              "byteEnd" => index_end,
            },
            "features" => [
              {
                "did" => did, # this is the matched mention
                "$type" => "app.bsky.richtext.facet#mention",
              },
            ],
          )
        end
      end

      # Find links
      text.enum_for(:scan, link_pattern).each do |m|
        index_start = Regexp.last_match.offset(0).first
        index_end = Regexp.last_match.offset(0).last
        m.compact!
        next unless m[1]

        path = "#{m[1]}#{m[2..-1].join("")}".strip.gsub(%r(/{2,}), '/')

        facets.push(
          "$type" => "app.bsky.richtext.facet",
          "index" => {
            "byteStart" => index_start,
            "byteEnd" => index_end,
          },
          "features" => [
            {
              "uri" => URI.parse("#{m[0]}://#{path}").normalize.to_s,
              "$type" => "app.bsky.richtext.facet#link",
            },
          ],
        )
      end

      facets
      # facets.empty? ? nil : facets
    end
  end
end

module Bskyrb
  class PostRecord
    include ATProto::RequestUtils
    include PostTools
    attr_accessor :text, :timestamp, :facets, :embed, :pds

    def initialize(text, timestamp: DateTime.now.iso8601(3), pds: "https://bsky.social")
      @text = text
      @timestamp = timestamp
      @pds = pds
    end

    def to_json_hash
      {
        text: @text,
        createdAt: @timestamp,
        "$type": "app.bsky.feed.post",
        facets: @facets,
      }
    end

    def create_facets!()
      @facets = create_facets(@text)
    end
  end
end
