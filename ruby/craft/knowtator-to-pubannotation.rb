#!/usr/bin/env ruby
require 'xml'
require 'json'

txtdir = 'txt'
outdir = nil

require 'optparse'
optparse = OptionParser.new do |opts|
  opts.banner = "Usage: craft-knowtator-to-pa-json.rb [option(s)] id"

  opts.on('-t', '--text directory', 'specifies the text directory.') do |d|
    txtdir = d
  end

  opts.on('-o', '--output directory', 'specifies the output directory.') do |d|
    outdir = d
  end

  opts.on('-h', '--help', 'displays this screen') do
    puts opts
    exit
  end
end

optparse.parse!

puts "Text directory: #{txtdir}"
puts "Output directory: #{outdir}"

if !outdir.nil? && !File.exists?(outdir)
  Dir.mkdir(outdir)
  puts "Output directory, #{outdir}, created."
end

ARGV.each do |f|
  id      = File.basename(f, ".txt.knowtator.xml")
  text    = File.read(txtdir + '/' + id + '.txt').chomp
  outfile = id + '.json'
  outfile = outdir + '/' + outfile unless outdir.nil?

  denotations = []
  doc = XML::Document.file(f)
  anns = doc.find('/annotations/annotation')
  anns.each do |ann|
    mention = ann.find_first('mention')
    m = mention[:id]
    span = ann.find_first('span')
    b = span[:start].to_i
    e = span[:end].to_i
    denotations << {:span => {:begin => b, :end => e}, :obj => m}
  end

  annotations = {:text => text, :denotations => denotations}

  File.open(outfile, 'w') {|f| f.write(annotations.to_json)}
  puts outfile
end
