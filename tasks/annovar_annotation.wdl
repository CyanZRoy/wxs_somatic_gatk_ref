task annovar_annotation {

    # Input from filter_and_select_pass_variants task.
    File filtered_vcf
    String tumor_sample_name

    # ANNOVAR database directory, e.g. humandb.
    File annovar_database

    String buildver = "hg19"
    String protocols = "refGene,clinvar_20240917,dbnsfp47a,cosmic103_genome"
    String operations = "g,f,f,f"
    String cluster_config
    String docker_image

    String output_prefix = "${tumor_sample_name}"

    Int raw_disk_gb = ceil(ceil(size(filtered_vcf, "GB") * 4)) + 420
    Int disk_gb = if raw_disk_gb > 1000 then 1000 else raw_disk_gb

    command <<<
        set -e
        call_dir="$PWD"
        copy_task_logs() {
            cp -f "$call_dir/script" "$call_dir/script.txt" 2>/dev/null || true
            cp -f "$call_dir/stdout" "$call_dir/stdout.txt" 2>/dev/null || true
            cp -f "$call_dir/stderr" "$call_dir/stderr.txt" 2>/dev/null || true
        }
        trap copy_task_logs EXIT
        local_work="/tmp/${tumor_sample_name}_annovar"
        mkdir -p "$local_work"
        cp -f ${filtered_vcf} "$local_work/input.vcf.gz"
        cd "$local_work"

        variant_count=$(gzip -cd input.vcf.gz | awk 'BEGIN{n=0} !/^#/ {n++} END{print n}')
        if [ "$variant_count" -eq 0 ]; then
            gzip -cd input.vcf.gz > ${output_prefix}.${buildver}_multianno.vcf
            printf 'Chr\tStart\tEnd\tRef\tAlt\tFunc.refGene\tGene.refGene\tGeneDetail.refGene\tExonicFunc.refGene\tAAChange.refGene\tclinvar_20240917\tdbnsfp47a\tcosmic103_genome\tOtherinfo\n' > ${output_prefix}.${buildver}_multianno.txt
            cp -f ${output_prefix}.${buildver}_multianno.vcf ${output_prefix}.${buildver}_multianno.txt "$call_dir"/
            exit 0
        fi

        /installations/annovar/table_annovar.pl input.vcf.gz \
            ${annovar_database} \
            -buildver ${buildver} \
            -out ${output_prefix} \
            -remove \
            -protocol ${protocols} \
            -operation ${operations} \
            -nastring . \
            -vcfinput \
            -thread $(nproc)
        cp -f ${output_prefix}.${buildver}_multianno.vcf ${output_prefix}.${buildver}_multianno.txt "$call_dir"/
    >>>

    output {
        File annotated_vcf = "${output_prefix}.${buildver}_multianno.vcf"
        File annotated_txt = "${output_prefix}.${buildver}_multianno.txt"
    }

    runtime {
        docker: docker_image
        instanceTypes: [cluster_config]
        systemDisk: "cloud " + disk_gb
    }
}
