#!/usr/bin/env ruby
module PubAnnotation; end unless defined? PubAnnotation

class << PubAnnotation
  def load_bionlp_st (txt, a1, a2)
    a1_anns = a1.split(/\n/).collect {|l| l.split(/\t/)[0..1]}
    a2_anns = a2.split(/\n/).collect {|l| l.split(/\t/)[0..1]}

    denotations = Array.new
    relations = Array.new
    modifications = Array.new

    a1_anns.each do |id, ann|
      c, b, e = ann.split(/ /)
      denotations << {:id=> id, :span => {:begin => b, :end => e}, :obj => c}
    end

    rid = 0
    spans = {}

    ## 1st round
    a2_anns.each do |id, ann|

      if id =~ /^T/
        c, b, e = ann.split(/ /)
        if ((c == 'Protein') || (c == 'Entity')) 
          denotations << {:id=> id, :span => {:begin => b, :end => e}, :obj => c}
        end
        spans[id] = {:begin => b, :end => e};
      end

    end

    partofrel = []

    ## 2nd round
    a2_anns.each do |id, ann|

      if id =~ /^\*/
        arg = ann.split(/ /)
        o  = arg[1]
        ss = arg[2..-1]
        ss.each do |s|
          relations << {:id=> "R#{rid+=1}", :pred => 'equivalentTo', :subj => s, :obj => o}
        end
      end

      if id =~ /^E/
        arg = ann.split(/ /)

        ## instantiation of the event
        r, o = arg.shift.split(/:/)
        denotations << {:id => id, :span => spans[o], :obj => r}

        theme = Array.new
        cause = nil
        site = Array.new
        csite = nil
        toloc = nil
        atloc = nil
        fromloc = nil

        arg.each do |a|
          r, o = a.split(/:/)
          case r
          when 'Theme'
            theme[0] = o
          when /Theme([1-9])/
            i = $1.to_i - 1 
            theme[i] = o
          when 'Site'
            site[0] = o
          when /Site([1-9])/
            i = $1.to_i - 1
            site[i] = o
          when 'CSite'
            csite = o
          when 'Cause'
            cause = o
          when 'ToLoc'
            toloc = o
          when 'AtLoc'
            atloc = o
          when 'FromLoc'
            fromloc = o
          else
            warn "unknown argument: #{r}"
          end
        end

        theme.each_with_index do |t, i|
          if site[i]
            relations << {:id => "R#{rid+=1}", :pred => 'themeOf', :subj => site[i], :obj => id}
            unless (partofrel.include?("#{site[i]}-#{theme[i]}"))
              relations << {:id => "R#{rid+=1}", :pred => 'partOf',  :subj => site[i], :obj => theme[i]}
              partofrel.push("#{site[i]}-#{theme[i]}")
            end
          else
            relations << {:id => "R#{rid+=1}", :pred => 'themeOf', :subj => theme[i], :obj => id}
          end
        end

        if cause
          if csite
            relations << {:id => "R#{rid+=1}", :pred => 'causeOf', :subj => csite, :obj => id}
            unless (partofrel.include?("#{csite}-#{cause}"))
              relations << {:id => "R#{rid+=1}", :pred => 'partOf',  :subj => csite, :obj => cause}
              partofrel.push("#{csite}-#{cause}")
            end
          else
            relations << {:id => "R#{rid+=1}", :pred => 'causeOf', :subj => cause, :obj => id}
          end
        end

        if toloc
          relations << {:id => "R#{rid+=1}", :pred => 'locationOf', :subj => toloc, :obj => id}
        end

        if atloc
          relations << {:id => "R#{rid+=1}", :pred => 'locationOf', :subj => atloc, :obj => id}
        end

        if fromloc
          relations << {:id => "R#{rid+=1}", :pred => 'fromLocationOf', :subj => fromloc, :obj => id}
        end

      end

      if id =~ /^M/
        modtype, modobj = ann.split(/ /)
        modifications << {:id => id, :pred => modtype, :obj => modobj}
      end

    end

    {:text => txt, :denotations => denotations, :relations => relations, :modifications => modifications}
  end

  def load_bionlp_st_coref (txt, a1, a2)
    a1_anns = a1.split(/\n/).collect {|l| l.split(/\t/)[0..1]}
    a2_anns = a2.split(/\n/).collect {|l| l.split(/\t/)[0..1]}

    ## index spans
    spans = {}

    a1_anns.each do |id, ann|
      c, b, e = ann.split(/ /)
      spans[id] = {:begin => b, :end => e}
    end

    a2_anns.each do |id, ann|
      if id =~ /^T/
        c, b, e = ann.split(/ /)
        spans[id] = {:begin => b, :end => e}
      end
    end

    ## collect denotations and relations
    denotations = []
    relations = []

    a2_anns.each do |id, ann|

      if id =~ /^R/
        t, s, o = ann.split(/ /)
        s = s.split(/:/)[1]
        o = o.split(/:/)[1]
        if t == 'Coreference'
          denotations << {:id=> s, :span => spans[s], :obj => "Anaphor"}
          denotations << {:id=> o, :span => spans[o], :obj => "Antecedent"}
          relations << {:id=> id, :pred => 'boundBy', :subj => s, :obj => o}
        end
      end

    end
    denotations.uniq!

    {:text => txt, :denotations => denotations, :relations => relations}
  end

end


if __FILE__ == $0
  require 'json'

  odir = './';
  mode = nil;

  ## command line option processing
  require 'optparse'
  optparse = OptionParser.new do|opts|
    opts.banner = "Usage: bionlp-st-to-pubann-json.rb [options] a2_file(s)"

    opts.on('-o', '--output directory', "specifies the output directory. default: #{odir}") do |d|
      odir = d
    end

    opts.on('-a', '--anaphora', 'tells it to convert anaphora annotation') do
      mode = :anaphora
    end

    opts.on('-h', '--help', 'displays this screen') do
      puts opts
      exit
    end
  end

  optparse.parse %w[--help] unless ARGV.length > 0
  optparse.parse!

  ARGV.each do |ff|
    ## filename checking : needs to be configured.
    fpath = ff.sub(/\.(txt|a1|a2)$/, '')
    fname = fpath.split(/\//).last
    sourcedb, sourceid, divid, section = fname.split(/[-]/)
    next unless (((sourcedb == 'PubMed') || (sourcedb == 'PMC')) && (sourceid =~ /^[0-9]+$/))

    if sourcedb == 'PMC'
      if divid =~ /^[0-9]+$/
        divid = divid.to_i
      else
        warn "> no divid: #{fname}"
        next
      end
    else
      divid = nil
    end

    ## read files
    txt = File.read(fpath + '.txt')
    a1  = File.read(fpath + '.a1')
    a2  = File.read(fpath + '.a2')

    ## parsing
    annotations = (mode == :anaphora) ? PubAnnotation::load_bionlp_st_coref(txt, a1, a2) : PubAnnotation::load_bionlp_st(txt, a1, a2)
    annotations[:sourcedb] = sourcedb
    annotations[:sourceid] = sourceid
    annotations[:divid] = divid unless divid.nil?

    if (odir)
      unless File.exists?(odir)
        Dir.mkdir(odir)
        puts "> output directory, #{odir}, created."
      end

      outfilename = fname + '.json'
      puts outfilename
      File.open(odir + '/' + outfilename, 'w') {|f| f.write(annotations.to_json)}
    end
  end
end
