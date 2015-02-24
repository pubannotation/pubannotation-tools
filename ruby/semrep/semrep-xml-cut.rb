#!/usr/bin/env ruby
odir = 'semrep'

file = File.read(ARGV[0])
docs = file.split(/\n\n/)
docs.each do |d|
  d =~ %r|Document id="([1-9][0-9]*)"|
  pmid = $1
  p pmid
  outfilename = "PubMed-#{pmid}-TIAB.xml"
  File.open(odir + '/' + outfilename, 'w') {|f| f.write(d)}
end
