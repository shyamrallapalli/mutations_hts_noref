#!/usr/bin/ruby
# encoding: utf-8
#

require 'bio'
require 'bio-samtools'

### command line input
### ruby ordered_fasta_vcf_positions 'ordered fasta file' 'shuffled vcf file'  writes ordered variant positions to text files and
### a vcf file with name corrected contigs/scaffolds and "AF" entry to info field

assembly_len = 0
### Read ordered fasta file and store sequence id and lengths in a hash
sequences = Hash.new {|h,k| h[k] = {} }
file = Bio::FastaFormat.open(ARGV[0])
file.each do |seq|
	sequences[seq.entry_id] = assembly_len
	assembly_len += seq.length.to_i
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

### Read sequence fasta file and store sequences in a hash
contigs = Hash.new{ |h,k| h[k] = Hash.new(&h.default_proc) }
infile = ARGV[1]
File.open(infile, 'r').each do |line|
	next if line =~ /^#/
	v = Bio::DB::Vcf.new(line)
	v.chrom = rename_chr(v.chrom)
	v.pos = v.pos.to_i + sequences[v.chrom]
	if v.info["HOM"].to_i == 1
		contigs[:hm][v.pos] = 1
	elsif v.info["HET"].to_i == 1
		contigs[:ht][v.pos] = 1
	end
end

# New file is opened to write
def open_new_file_to_write(input, number)
	outfile = File.new("per-#{number}bp-#{input}.txt", "w")
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

breaks = [10000, 50000, 100000, 500000, 1000000]
breaks.each do | step |
	outfile = open_new_file_to_write(infile, step)
	distribute = Hash.new{ |h,k| h[k] = Hash.new(&h.default_proc) }
	distribute = pool_variants_per_step(contigs, step, distribute, :hm)
	distribute = pool_variants_per_step(contigs, step, distribute, :ht)
	distribute.each_key do | key |
		hm = 0
		ht = 0
		if distribute[key].key?(:hm)
			hm = distribute[key][:hm]
		end
		if distribute[key].key?(:ht)
			ht = distribute[key][:ht]
		end
		outfile.puts "#{key}\t#{hm}\t#{ht}"
	end
end