#!/usr/bin/env ruby

require 'net/http'
require 'open-uri'
require 'json'

url = 'http://a1.phobos.apple.com/us/r1000/000/Features/atv/AutumnResources/videos/entries.json'
uri = URI(url)

entries = JSON.parse(Net::HTTP.get(uri))

assets = entries.map { |entry| entry["assets"] }

assets.flatten().map { |asset| asset["url"] }.each do |urlString|
    filename = urlString.split('/').last
    filepath = "/Users/mlong/Downloads/atv/ruby/#{filename}"

    unless File.exist?(filepath)
        puts "Downloading #{urlString}"
        File.open(filepath, "wb") do |save_location|
            open(urlString, "rb") do |read_file|
                save_location.write(read_file.read)
                puts "Saved file to #{filepath}"
            end
        end
    end
end

puts "All files downloaded"


