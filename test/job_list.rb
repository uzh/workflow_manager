#!/usr/bin/env ruby
# encoding: utf-8
# Version = '20210618-154525'


require 'redis'
db0 = Redis.new(port: 6380, db: 0)
db1 = Redis.new(port: 6380, db: 1)
db2 = Redis.new(port: 6380, db: 2)
puts "db0"
puts ["JobID", "Status"].join("\t")
db0.keys.sort.each do |key|
  value = db0.get(key)
  puts [key, value].join("\t")
end

puts
puts "db1"
db1.keys.sort.each do |key|
  value = db1.get(key)
  puts [key, value].join("\t")
end

puts
puts "db2"
db2.keys.sort.each do |key|
  value = db2.get(key)
  puts [key, value].join("\t")
end
