#!/bin/bash

#########dDocent 1.0##################################################################################


#This script serves as an interactive bash wrapper to QC, assemble, map, and call SNPs from double digest RAD data.
#It requires that your raw data are split up by tagged individual and follow the naming convenction of:

#Sample1.F.fq and Sample1.R.fq

#############################################################################################

NumInd=$(ls *.F.fq | wc -l)
NumInd=$(($NumInd - 0))

echo -e "dDocent 1.0 by J. Puritz for Gold lab \n"
echo -e "Contact jpuritz@gmail.com with any problems \n\n "

if [ $NumInd -gt 9 ]
        then
	MinAll=0.05
        MaxSize=9
        else
	MinAll=$(echo "scale=2; 1 / (2 * $NumInd) " | bc)
        MaxSize=$(( $NumInd - 1 ))
fi


ls *.F.fq > namelist
sed -i 's/.F.fq//g' namelist
NAMES=( `cat "namelist" `)

ls -S *.F.fq > sizelist
sed -i 's/.F.fq//g' sizelist
SIZE=( `cat "sizelist" `)


echo "$NumInd individuals are detected is this correct? Enter yes or no and press [ENTER]"

read Indcorrect

if [ "$Indcorrect" == "no" ]; then
        echo "Please double check that all fastq files are named Ind01.F.fq and Ind01.R.fq"
        exit 1
elif [ "$Indcorrect" == "yes" ]; then
    	echo "Proceeding with $NumInd individuals"
else
	echo "Incorrect Input"
	exit 1
fi

echo "Were these reads processed with STACKS process_radtags?  Type yes or no and press [Enter]"
echo "If you don't know, answer yes."

read STACKS

if [ "$STACKS" == "yes" ]; then

	echo "The _1 character will be replaced with /1 in the name of every sequence"
	
elif [ "$STACKS" == "no" ]; then
    	echo "Proceeding with out sequence name alteration"
else
	echo "Incorrect input, assuming no."
fi

echo "Do you want to quality trim your reads?" 
echo "Answering yes will simultaneously trim reads and perform reference assembly"
echo "Type yes or no and press [ENTER]?"

read TRIM

if [ "$TRIM" == "yes" ]; then
	echo "Reads will be trimmed and simultaneously assembled"
	echo "Reads will be assembled with Rainbow"
    echo "CD-HIT will cluster reference sequences by similarity. The -c parameter (% similarity to cluster) may need to be changed for your taxa."
    echo "Would you like to enter a new c parameter now? Type yes or no and press [ENTER]"
    read optC
    echo $optC
    if [ "$optC" == "no" ]; then
            echo "Proceeding with default 0.9 value."
            simC=0.9
        elif [ "$optC" == "yes" ]; then
            echo "Please enter new value for c. Enter in decimal form (For 90%, enter 0.9)"
            read newC
            simC=$newC
        else
            echo "Incorrect input. Proceeding with the default value."
            simC=0.9
        fi
        
else
	echo "Do you need to perform an assembly? Type no and press [ENTER] if you want to skip to read mapping and SNP calling"
	read ASSEMBLY
	if [ "$ASSEMBLY" == "yes" ]; then
		echo "Reads will be assembled with Rainbow"
		echo "CD-HIT will cluster reference sequences by similarity. The -c parameter (% similarity to cluster) may need to be changed for your taxa"
		echo "Would you like to enter a new c parameter now? Type yes or no and press [ENTER]"
		read optC2
			if [ "$optC2" == "no" ]; then
        		echo "Proceeding with default 0.9 value."
				simC=0.9	
			elif [ "$optC2" == "yes" ]; then
    			echo "Please enter new value for c. Enter in decimal form (For 90%, enter 0.9)"
				read newC2
				simC=$newC2
			else
				echo "Incorrect input. Proceeding with the default value."
				simC=0.9
			fi
	fi
fi

echo "BWA will be used to map reads.  You may need to adjust -A -B and -O parameters for your taxa."
echo "Would you like to enter a new parameters now? Type yes or no and press [ENTER]"
read optq

if [ "$optq" == "yes" ]; then
        echo "Please enter new value for A (match score).  It should be an integer.  Default is 1."
        read newA
        optA=$newA
                echo "Please enter new value for B (mismatch score).  It should be an integer.  Default is 4."
        read newB
        optB=$newB
                echo "Please enter new value for O (gap penalty).  It should be an integer.  Default is 6."
        read newO
        optO=$newO
else
                echo "Proceeding with default values for BWA read mapping."
                optA=1
                optB=4
                optO=6
fi

echo ""
echo "Please enter your email address.  dDocent will email you when it is finished running."
echo "Don't worry; dDocent has no financial need to sell your email address to spammers."
read MAIL
echo ""
echo ""
echo "At this point, all configuration information has been enter and dDocent may take several hours to run." 
echo "It is recommended that you move this script to a background operation and disable terminal input and output."
echo "All data and logfiles will still be recorded."
echo "To do this:"
echo "Press control and Z simultaneously"
echo "Type 'bg' without the quotes and press enter"
echo "Type 'disown -h' again without the quotes and press enter"
echo ""
echo "Now sit back, relax, and wait for your analysis to finish."

main(){
if [ "$STACKS" == "yes" ]; then

	echo "Removing the _1 character and replacing with /1 in the name of every sequence"
	for i in "${NAMES[@]}"
	do	
	sed -e 's:_2$:/2:g' $i.R.fq > $i.Ra.fq
	sed -e 's:_1$:/1:g' $i.F.fq > $i.Fa.fq
	mv $i.Ra.fq $i.R.fq
	mv $i.Fa.fq $i.F.fq
	done

fi


if [ "$TRIM" == "yes" ]; then
	echo "Trimming reads and simultaneously assemblying reference sequences"	
	TrimReads & 2> trim.log
	setupRainbow 2> rainbow.log
	wait
else
	if [ "$ASSEMBLY" == "yes" ]; then
		setupRainbow 2> rainbow.log
	fi
fi

##Use BWA to map reads to assembly

bwa0.7 index -a bwtsw referencegenome &> index.log

for i in "${NAMES[@]}"
do
bwa0.7 mem referencegenome $i.R1.fq $i.R2.fq -t 32 -a -T 10 -A $optA -B $optB -O $optO > $i.sam 2> bwa.$i.log
done

##Convert Sam to Bam and remove low quality, ambiguous mapping
for i in "${NAMES[@]}"
do
samtools view -bT referencegenome -q1 $i.sam > $i.bam 2>$i.bam.log
samtools sort $i.bam $i
done

samtools faidx referencegenome

#Calling of SNPs from two samples must have a minimum read of depth of 10 and below 200 with a minimum quality score of 20
echo "Using samtools to pileup reads"
samtools mpileup -D -f referencegenome *.bam >mpileup 2> mpileup.log
echo "Using VarScan2 to call SNPs with at least 5 reads (within 1 individual), 95% probability, and at least 2 reads for the minor allele"
java -jar /usr/local/bin/VarScan.v2.3.5.jar mpileup2snp mpileup --output-vcf --min-coverage 5 --strand-filter 0 --min-var-freq 0.1 --p-value 0.05 >SNPS.vcf 2>varscan.log

###Code to rename samples in VCF file
echo "Renaming samples in VCF file."
j=( `wc -l namelist `)
h=1
while [ $h -le $j ]
do
t="Sample"$h
b=$h-1
SS1="$t"
SS2="${NAMES[$b]}"
sed -i 's/'$t'/'$SS2'/' SNPS.vcf 
let h++
done

echo "Using VCFtools to parse SNPS.vcf for SNPS that are not indels and are called in at least 90% of individuals"
vcftools --vcf SNPS.vcf --geno 0.9 --out Final --counts --recode --non-ref-af 0.001 --remove-indels &>VCFtools.log

tail Final.log	

if [ ! -d "logfiles" ]; then
mkdir logfiles
fi
mv *.txt *.log log ./logfiles 2> /dev/null

echo -e "dDocent has finished with an analysis in" `pwd` "\n\n"`date` "\n\ndDocent 1.0 \nThe 'd' is silent, hillbilly." | mailx -s "dDocent has finished" $MAIL
}

TrimReads () 
{ for i in "${NAMES[@]}"
do
echo "Trimming Sample $i"
trim_galore --paired -q 10 --length 20 -a GATCGGAAGAGCACACGTCTGAACTCCAGTCACNNNNNNATATCGTATGCCGTCTTCTGCTTG -a2 GATCGGAAGAGCGTCGTGTAGGGAAAGAGTGTAGATCTCGGTGGTCGCCG --stringency 10 $i.F.fq $i.R.fq 2> $i.trim.log
mv $i.F_val_1.fq $i.R1.fq
mv $i.R_val_2.fq $i.R2.fq
done
}

#Use Rainbow to cluster and assemble reads

setupRainbow ()
{ echo "Concatenating F and R reads of up to 10 individuals for assembly"
cat ${SIZE[0]}.F.fq > forward
cat ${SIZE[0]}.R.fq > reverse

for ((i = 1; i <= $MaxSize; i++));
do
cat ${SIZE[$i]}.F.fq >> forward
cat ${SIZE[$i]}.R.fq >> reverse
done

seqtk seq -r forward > forwardRC
mergefq.pl reverse forwardRC concat.fq

#Use Rainbow to cluster and assemble reads
echo "Using rainbow to cluster and assemble reads"
rainbow cluster -1 concat.fq -m 6 > cat.rbcluster.out 2> log
rainbow div -i cat.rbcluster.out -o cat.rbdiv.out -f $MinAll
rainbow merge -a -i cat.rbdiv.out -o cat.rbasm.out
select_best_rbcontig.pl cat.rbasm.out > rainbow
cat rainbow | sed s/./N/96 | sed s/./N/97 | sed s/./N/98 | sed s/./N/99 | sed s/./N/100 | sed s/./N/101 | sed s/./N/102 | sed s/./N/103 | sed s/./N/104 | sed s/./N/105 > rainbowN
cd-hit-est -i rainbowN -o referencegenome -T 0 -c $simC -M 0 -l 30 &>cdhit.log
}

main
