#!/usr/bin/ruby
# encoding: utf-8
#
require 'bio'

genes = Hash.new {|h,k| h[k] = {} }
file = Bio::FastaFormat.open(ARGV[0])
file.each do |entry|
	genes[entry.entry_id] = entry.length
end

blast = Hash.new{ |h,k| h[k] = Hash.new(&h.default_proc) } ## vivified hash
lines = File.read(ARGV[1])
results = lines.split("\n")
results.each do |string|
	if string !~ /^#/
		alninfo = string.split("\t")
		if alninfo[2].to_f > 90.0 # % identity selection
			if alninfo[9].to_i > alninfo[8].to_i
				blast[alninfo[0]][alninfo[1]]["plus"][alninfo[8].to_i][alninfo[6].to_i] = string
				#	  qurey id	  subject id  strand	subject start	query start		  blast-data
			else
				blast[alninfo[0]][alninfo[1]]["minus"][alninfo[8].to_i][alninfo[6].to_i] = string
				#	  qurey id	  subject id  strand	subject start	query start		  blast-data
			end
		end
	end
end

def return_aln_parameters_query (blasth)
	data = Hash.new{ |h,k| h[k] = Hash.new(&h.default_proc) } ## vivified hash
	blasth.each_key { |s_id|		# subject id keys
		blasth[s_id].each_key { |strand|		# subject aln start keys sorted
			q_start, q_end, s_start, s_end = 0, 0, 0, 0
			number = 1
			blasth[s_id][strand].keys.sort.each { |sub_start|		# subject aln start keys sorted
				blasth[s_id][strand][sub_start].keys.sort.each { |que_start|		# query aln start keys sorted
					alninfo = blasth[s_id][strand][sub_start][que_start]
					array = alninfo.split("\t")
					block = ''
					if q_start == 0 and q_end == 0 and s_start == 0 and s_end == 0
						block = [s_id, strand, number].join("_")
						data[block]["alnlength"] = array[3].to_i
						data[block]["alns"][alninfo] = 1
						q_start, q_end, s_start, s_end = array[6], array[7], array[8], array[9]
					else
						sub_diff = 0
						que_diff = 0
						if strand == "plus"
							sub_diff = array[8] - s_end
							que_diff = array[6] - q_end
						else
							sub_diff = array[9] - s_start
							que_diff = q_start - array[7]
						end
						if sub_diff <  que_diff + 5000
								data[block]["alnlength"] += array[3].to_i
								data[block]["alns"][alninfo] = 1
						else
							number += 1
							block = [s_id, strand, number].join("_")
							data[block]["alnlength"] = array[3].to_i
							data[block]["alns"][alninfo] = 1
							q_start, q_end, s_start, s_end = array[6], array[7], array[8], array[9]
						end
					end
				}
			}
		}
	}
	return data
end

def return_best_contig_aln (hash2)
	contigid = ""
	goodhits = 0
	hash2.each_key { |key|
		if contigid =~ /\w/
			if hash2[key]["alnlength"] > hash2[contigid]["alnlength"]
				contigid = key
				goodhits = 1
			elsif hash2[key]["alnlength"] == hash2[contigid]["alnlength"]
				goodhits += 1
			end
		else
			contigid = key
		end
	}
	return contigid, goodhits
end


#gff = Hash.new {|h,k| h[k] = Hash.new {|h,k| h[k] = Hash.new {|h,k| h[k] ={} } } }
gff = Hash.new{ |h,k| h[k] = Hash.new(&h.default_proc) } ## vivified hash

blast.each { |k1,v1|
  data2 = return_aln_parameters_query(blast[k1])
  subjectid, numgood = return_best_contig_aln(data2)
  if subjectid =~ /\w/ and numgood == 1
	genelen_cov = (100* data2[subjectid]["alnlength"].to_i)/genes[k1].to_i
	#mismatch_cov = (100* data2[subjectid]["mismatch"].to_i)/genes[k1].to_i
	if genelen_cov >= 80 and mismatch_cov <=10
		limits = Hash.new {|h,k| h[k] = {} }
		contignum = ""
		if subjectid =~ /\_(\d+)$/
			contignum = $1.chomp.to_i
		#	puts contignum
		end

		blast[k1][subjectid].each { |key2, value2|
			array2 = key2.split("\t")
			aln_end = array2[9].to_i
			aln_start = array2[8].to_i
			# puts "#{k1}\t#{aln_end}\t#{aln_start}\n"
			if aln_end < aln_start
				# outfile.puts "#{subjectid}\tTRINITY\texon\t#{aln_end}\t#{aln_start}\t.\t-\t.\tParent=#{k1};Target=#{k1} #{array2[6].to_i} #{array2[7].to_i}\n"
				info = "#{subjectid}\tTRINITY\texon\t#{aln_end}\t#{aln_start}\t.\t-\t.\tParent=#{k1};Target=#{k1} #{array2[7].to_i} #{array2[6].to_i};Genelength=#{genes[k1]}".to_s
				gff[contignum][subjectid][aln_end][k1][:exon][info] = 1
				limits[:strand] = "-"
				if limits.key?(:start) == true
					if limits[:start] > aln_end
						limits[:start] = aln_end
					end
				else
					limits[:start] = aln_end
				end
				if limits.key?(:stop) == true
					if limits[:stop] < aln_start
						limits[:stop] = aln_start
					end
				else
					limits[:stop] = aln_start
				end
			elsif aln_end > aln_start
				# outfile.puts "#{subjectid}\tTRINITY\texon\t#{aln_start}\t#{aln_end}\t.\t+\t.\tParent=#{k1};Target=#{k1} #{array2[6].to_i} #{array2[7].to_i}\n"
				info = "#{subjectid}\tTRINITY\texon\t#{aln_start}\t#{aln_end}\t.\t+\t.\tParent=#{k1};Target=#{k1} #{array2[6].to_i} #{array2[7].to_i};Genelength=#{genes[k1]}".to_s
				gff[contignum][subjectid][aln_start][k1][:exon][info] = 1
				limits[:strand] = "+"
				if limits.key?(:start) == true
					if limits[:start] > aln_start
						limits[:start] = aln_start
					end
				else
					limits[:start] = aln_start
				end
				if limits.key?(:stop) == true
					if limits[:stop] < aln_end
						limits[:stop] = aln_end
					end
				else
					limits[:stop] = aln_end
				end
			end
		}

		# outfile.puts "#{subjectid}\tTRINITY\tmRNA\t#{limits[:start]}\t#{limits[:stop]}\t.\t#{limits[:strand]}\t.\tID=#{k1}\n"
		info = "#{subjectid}\tTRINITY\tmRNA\t#{limits[:start]}\t#{limits[:stop]}\t.\t#{limits[:strand]}\t.\tID=#{k1};Parent=#{k1}".to_s
		gff[contignum][subjectid][limits[:start]][k1][:mRNA][info] = 1
		info2 = "#{subjectid}\tTRINITY\tgene\t#{limits[:start]}\t#{limits[:stop]}\t.\t#{limits[:strand]}\t.\tID=#{k1}".to_s
		gff[contignum][subjectid][limits[:start]][k1][:gene][info2] = 1
	end

  end
}

# New file is opened to write the gff info
def open_new_file_to_write (number)
outfile = ""
	outfile = File.new("Blastn_to_gff3-#{number}.gff", "w")
	outfile.puts "##gff-version 3"
	outfile.puts "##mRNA row have 'Genelength' attribute presenting length of RNA-seq contig and exon rows have 'Target' attibute depicting start and stop mRNA match part"
outfile
end

number = 1
printfile = open_new_file_to_write(number)
puts printfile
counter = 500050
gff.sort.map do |num, v1|
 gff[num].each { |id, v2|
	if counter < 50
	  	number = number + 1
		printfile = open_new_file_to_write(number)
		counter = 500050
		puts printfile
	end
	gff[num][id].sort.map do |position, v3|
		gff[num][id][position].sort.map do |gene, v4|
		  reverse = Hash[gff[num][id][position][gene].sort.reverse]
		  reverse.each { |feature, v5|
			reverse[feature].each { |key, v6|
				printfile.puts "#{key}"
				counter -= 1
			}
		  }
	  	end
	end
  }
end
