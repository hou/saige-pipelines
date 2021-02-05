task summary{
    File input_file
    File finngen_annotation
    File gnomad_annotation
    File finngen_tbi = finngen_annotation + ".tbi"
    File gnomad_tbi = gnomad_annotation + ".tbi"
    
    Float pval_thresh
    String pheno
    String output_name=pheno+"_summary"
    String docker

    command <<<
        python3 <<EOF
        #read file
        fname = "${input_file}"
        finngen_annotation_file = "${finngen_annotation}"
        gnomad_annotation_file  = "${gnomad_annotation}"
        sig_threshold = ${pval_thresh}
        output_name = "${output_name}"
                    
        import pysam
        import gzip
        from typing import NamedTuple

        FGAnnotation = NamedTuple('FGAnnotation',[('gene',str),('consequence',str)])
        GnomadAnnotation = NamedTuple('GnomadAnnotation',[('finaf',str),('nfeaf',str),('rsid',str)])

        def get_header(reader,file):
            with reader(file, "rt") as f:
                l = f.readline()
                return l.strip("\n").split("\t")

        def get_fg_annotation(iterator,variant,gene_idx, consequence_idx) -> FGAnnotation:
            for v in iterator:
                cols = v.strip("\n").split("\t")
                if cols[0] == variant:
                    return FGAnnotation(cols[gene_idx],cols[consequence_idx])
            return FGAnnotation("","")

        def get_gnomad_annotation(iterator,cpra,finaf_idx, nfeaf_idx, rsid_idx) -> GnomadAnnotation:
            for v in iterator:
                cols = v.strip("\n").split("\t")

                if (cols[3] == "chr"+cpra[0]) and (cols[4] == str(cpra[1])) and (cols[5] == cpra[2]) and (cols[6] == cpra[3]):
                    return GnomadAnnotation(cols[finaf_idx],cols[nfeaf_idx],cols[rsid_idx])
            return GnomadAnnotation(".",".",".")


        #open finngen annotation tabix
        fg_tabix = pysam.TabixFile(finngen_annotation_file,parser=None)
        #get fg header column positions
        fg_header = get_header(gzip.open, finngen_annotation_file)
        gene_idx, cons_idx = (fg_header.index("gene_most_severe"),fg_header.index("most_severe"))
        #open gnomad annotation tabix
        gnomad_tabix = pysam.TabixFile(gnomad_annotation_file,parser=None)
        gd_header = get_header(gzip.open, gnomad_annotation_file)
        finaf_idx, nfeaf_idx, rsid_idx = (gd_header.index("fin.AF"),gd_header.index("nfsee.AF"),gd_header.index("rsid"))



        with gzip.open(fname, "rt") as file:
            #open output file
            with open(output_name,"w") as outfile:
                #read header
                header = file.readline().strip("\n").split('\t')
                #find p-value index
                pval_idx = header.index("pval")

                #add gene name, consequence, gnomad finnish af, nfsee af, rsid
                header.extend(["fin.AF","nfsee.AF","rsid","gene_most_severe","most_severe"])
                outfile.write("\t".join(header)+"\n")
                #read lines
                for line in file:
                    line_columns = line.strip("\n").split('\t')
                    pvalue = float(line_columns[pval_idx])
                    if pvalue < sig_threshold:
                        cpra= (line_columns[0],int(line_columns[1]),line_columns[2],line_columns[3])
                        variant = "{}:{}:{}:{}".format(cpra[0],cpra[1],cpra[2],cpra[3])
                        #annotate
                        fg_iter = fg_tabix.fetch(cpra[0],cpra[1]-1, cpra[1])
                        fg_a = get_fg_annotation(fg_iter,variant, gene_idx,cons_idx)

                        #annotate
                        gnomad_iter = gnomad_tabix.fetch("chr"+cpra[0].replace("23","X"),cpra[1]-1, cpra[1])
                        gd_a = get_gnomad_annotation(gnomad_iter,cpra,finaf_idx, nfeaf_idx, rsid_idx)

                        line_columns.extend([
                            gd_a.finaf,
                            gd_a.finaf,
                            gd_a.rsid,
                            fg_a.gene,
                            fg_a.consequence,
                        ])
                        #gather row
                        #write to file
                        outfile.write("\t".join(line_columns)+"\n")
        print("summary created")
        EOF
        bgzip ${output_name}

    >>>

    output {
        File out = output_name+".gz"
    }

    runtime {
        docker: "${docker}"
        cpu: 1
        memory: "10 GB"
        disks: "local-disk 200 HDD"
        zones: "europe-west1-b"
        preemptible: 2
    }
}