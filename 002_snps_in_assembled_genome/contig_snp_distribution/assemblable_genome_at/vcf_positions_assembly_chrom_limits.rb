#!/usr/bin/ruby
# encoding: utf-8
#

require 'bio'
require 'bio-samtools'

### command line input
### ruby ordered_fasta_vcf_positions 'ordered fasta file' 'shuffled vcf file' 'chr:position'  writes ordered variant positions to text files and
### a vcf file with name corrected contigs/scaffolds and "AF" entry to info field

fastafile = ARGV[0]
vcffile = ARGV[1]
gfffile = ARGV[2] # gff file of denovo assembly over the fasta file

### Read ordered fasta file and store sequence id and lengths in a hash
sequences = Hash.new {|h,k| h[k] = {} }
file = Bio::FastaFormat.open(fastafile)
file.each do |seq|
	sequences[seq.entry_id] = seq.length.to_i
end

# argument 3 provides the chromosome id and position of causative mutation seperated by ':'
# this is used to get position in the sequential order of the chromosomes
info = ARGV[3].split(/:/)
targetchr = info[0].to_s
mutant_posn = info[1].to_i
warn "mutation position genome\t#{mutant_posn}"


# using limits of 20Mb, 10Mb, 5Mb and 2Mb around the causative mutation
limits = [10000000, 5000000, 2500000, 1000000]
seq_limit = Hash.new {|h,k| h[k] = {} }
limits.each do | delimit |
	lower = 0
	if (mutant_posn - delimit) > 0
		lower = mutant_posn - delimit
	end

	upper = mutant_posn + delimit
	if upper > sequences[targetchr]
		upper = sequences[targetchr]
	end
	seq_limit[delimit*2] = [lower, upper].join(':')
end


def rename_chr(chr)
	if chr =~ /^Chr\d/
		chr.gsub!(/^Chr/, '')
	elsif chr =~ /^ChrM/
		chr.gsub!(/^ChrM/, 'mitochondria')
	elsif chr =~ /^ChrC/
		chr.gsub!(/^ChrC/, 'chloroplast')
	end
	chr
end

### Read gff and selected chromosome coverage is stored in a hash
assembly = Hash.new {|h,k| h[k] = {} }
gff3 = Bio::GFF::GFF3.new(File.read(gfffile))
gff3.records.each do | record |
	chr = rename_chr(record.seqname.to_s)
	if targetchr == chr
		if record.feature == 'gene'
			assembly[record.start.to_i] = [record.start, record.end].join("_")
		end
	end
end

### Use stored hash to calculate uncovered genomic region and add to a hash
nocov = Hash.new {|h,k| h[k] = {} }
curr_gap = 0
prev_end = 0
count = 1
assembly.keys.sort.each do | key |
	info = assembly[key].split("_")
	curr_start = info[0].to_i
	curr_end = info[1].to_i
	if prev_end == 0
		if curr_start > 1
			curr_gap += curr_start - 1
			nocov[count] = [prev_end, curr_start, curr_gap, "gap"].join("_")
			count += 1
		else
			nocov[count] = [curr_start, curr_end, curr_gap, "no-gap"].join("_")
			count += 1
		end
		prev_end = curr_end
	else
		gap = curr_start - prev_end
		if gap > 0
			curr_gap += gap
			nocov[count] = [prev_end, curr_start, curr_gap, "gap"].join("_")
			count += 1
			nocov[count] = [curr_start, curr_end, curr_gap, "no-gap"].join("_")
			count += 1
		else
			nocov[count] = [curr_start, curr_end, curr_gap, "no-gap"].join("_")
			count += 1
		end
		prev_end = curr_end
	end
end

def notin_asmbly_check(hash, varpos)
	subtract = 0
	is_gap = ''
	hash.keys.sort.each do | key |
		info = hash[key].split("_")
		start = info[0].to_i
		end_p = info[1].to_i
		if varpos.between?(start, end_p)
			subtract = info[2].to_i
			is_gap = info[3].to_s
			break
		end
	end
	[subtract, is_gap]
end

### Check if SNP's are in no sequence read coverage area and discard them
### And adjust remaining SNP position accordingly
subtract = 0
adjust_posn = 0

## cusative mutation position and adjust position in assembled parts
subtract, is_gap = notin_asmbly_check(nocov, mutant_posn)
adjust_posn = mutant_posn - subtract
warn "mutation position assembly\t#{adjust_posn}\t#{is_gap}"

### Read vcf file and store variants in respective
contigs = Hash.new{ |h,k| h[k] = Hash.new(&h.default_proc) }
varfile1 = File.new("varposn-chromosome-#{vcffile}.txt", "w")
varfile2 = File.new("varposn-assembly-#{vcffile}.txt", "w")
varfile1.puts "position\ttype"
varfile2.puts "position\ttype"
File.open(vcffile, 'r').each do |line|
	next if line =~ /^#/
	v = Bio::DB::Vcf.new(line)
	v.chrom = rename_chr(v.chrom)
	if targetchr == v.chrom
		v.pos = v.pos.to_i
		type = ''
		if v.info["HOM"].to_i == 1
			type = 'hm'
			varfile1.puts "#{v.pos}\t#{type}"
		elsif v.info["HET"].to_i == 1
			type = 'ht'
			varfile1.puts "#{v.pos}\t#{type}"
		end

		subtract, is_gap = notin_asmbly_check(nocov, v.pos)
		if is_gap == "no-gap"
			adj_pos = v.pos - subtract
			seq_limit.each_key do | limit |
				limits = seq_limit[limit].split(':')
				if v.pos.between?(limits[0].to_i, limits[1].to_i)
					pos = adj_pos - limits[0].to_i
					contigs[limit][type][pos] = 1
				end
			end
			varfile2.puts "#{adj_pos}\t#{type}"
		end
	end
end

# New file is opened to write
def open_new_file_to_write(input, number, region)
	outfile = File.new("#{region}-per#{number}bp-#{input}.txt", "w")
	outfile.puts "position\tnumhm\tnumht"
	outfile
end

def enumerate_snps(outhash, step, vartype)
	if outhash[step].has_key?(vartype)
		outhash[step][vartype] += 1
	else
		outhash[step][vartype] = 1
	end
	outhash
end

def pool_variants_per_step(inhash, step, outhash, vartype)
	slice = step
	inhash[vartype].keys.sort.each do | pos |
		if outhash[step].key?(vartype) == FALSE
			outhash[step][vartype] = 0
		end
		if pos <= step
			outhash = enumerate_snps(outhash, step, vartype)
		else
			num_loop = ((pos-step)/slice.to_f).ceil
			for i in 1..num_loop do
				step += slice
				if outhash[step].key?(vartype) == FALSE
					outhash[step][vartype] = 0
				end
			end
			outhash = enumerate_snps(outhash, step, vartype)
		end
	end
	outhash
end

breaks = [10000, 50000, 100000, 500000, 1000000, 2500000]
breaks.each do | step |
		contigs.each_key do | region |
		outfile = open_new_file_to_write(vcffile, step, region)
		distribute = Hash.new{ |h,k| h[k] = Hash.new(&h.default_proc) }
		distribute = pool_variants_per_step(contigs, step, distribute, 'hm')
		distribute = pool_variants_per_step(contigs, step, distribute, 'ht')
		distribute.each_key do | key |
			hm = 0
			ht = 0
			if distribute[key].key?('hm')
				hm = distribute[key]['hm']
			end
			if distribute[key].key?('ht')
				ht = distribute[key]['ht']
			end
			outfile.puts "#{key}\t#{hm}\t#{ht}"
		end
	end
end
