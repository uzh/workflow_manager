#!/usr/bin/env ruby
# encoding: utf-8
# Version = '20211001-104513'

PORT = (ARGV[0]||6380).to_i
require 'redis'
db0 = Redis.new(port: PORT, db: 0)
db1 = Redis.new(port: PORT, db: 1)
db2 = Redis.new(port: PORT, db: 2)
db4 = Redis.new(port: PORT, db: 4)

class Redis
  def show_all
    self.keys.sort.each do |key|
      value = self.get(key)
      puts [key, value].join("\t")
    end
  end
end

dbs = [db0, db1, db2, db4]
db_notes = ["state DB", "log DB", "project job DB", "JS tree DB"]

dbs.each.with_index do |db, i|
  note = db_notes[i]
  puts ["db#{i}", note].join("\t")
  db.show_all
  puts
end
exit
puts "db0, status DB"
puts ["JobID", "Status"].join("\t")
db0.keys.sort.each do |key|
  value = db0.get(key)
  puts [key, value].join("\t")
end

puts
puts "db1, log DB"
db1.keys.sort.each do |key|
  value = db1.get(key)
  puts [key, value].join("\t")
end

puts
puts "db2, status DB2, project specific"
db2.keys.sort.each do |key|
  value = db2.get(key)
  puts [key, value].join("\t")
end

puts
puts "db3, status DB3, project specific"
db3.keys.sort.each do |key|
  value = db3.get(key)
  puts [key, value].join("\t")
end
