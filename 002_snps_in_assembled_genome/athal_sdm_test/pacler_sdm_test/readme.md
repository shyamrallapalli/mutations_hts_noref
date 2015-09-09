### Testing SDM on pacbio assembled contig

#### Datasets

1.  From [Allen et al](http://journal.frontiersin.org/article/10.3389/fpls.2013.00362/full) backcross read data was used

2. Sequences for both mutant population and parent are available

3. Pacbio de-novo assembly of [Ler-1](http://datasets.pacb.com.s3.amazonaws.com/2014/Arabidopsis/reads/list.html) as assembled test genome

#### Analysis

1. `mutations_hts_noref/002_snps_in_assembled_genome/athal_sdm_test/Rakefile` outlines the analysis steps

2. Varscan calls of SNPs for mutant[bcf_fg_pacler.vcf] and parent [bcf_bg_pacler.vcf] are generated

3. Since genome used is Ler-1 and the mutants are from Col-0 there are many ecotype specific variants - resulting large vcf files

4. Used `filter_vcf_background.rb` script to filter out ecotype specific and parent specific variants and saved them to `filtered_bcf_fg_pacler.vcf`

5. VCF files being large, files are gzipped

6. 