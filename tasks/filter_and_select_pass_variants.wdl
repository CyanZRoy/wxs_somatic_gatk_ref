task filter_and_select_pass_variants {

    File mutect2_vcf
    File mutect2_vcf_index
    File mutect2_stats
    File read_orientation_model
    File contamination_table
    File tumor_segments
    String tumor_sample_name

    File ref_dir
    String fasta

    String docker_image
    String cluster_config

    String filtered_vcf_name = "${tumor_sample_name}.filtered.vcf.gz"
    String pass_vcf_name = "${tumor_sample_name}.pass.vcf.gz"

    Int raw_disk_gb = ceil(size(mutect2_vcf, "GB") * 5) + 420
    Int disk_gb = if raw_disk_gb > 1000 then 1000 else raw_disk_gb

    command <<<
        set -e -o pipefail
        call_dir="$PWD"
        copy_task_logs() {
            cp -f "$call_dir/script" "$call_dir/script.txt" 2>/dev/null || true
            cp -f "$call_dir/stdout" "$call_dir/stdout.txt" 2>/dev/null || true
            cp -f "$call_dir/stderr" "$call_dir/stderr.txt" 2>/dev/null || true
        }
        trap copy_task_logs EXIT
        local_work="/tmp/${tumor_sample_name}_filter"
        mkdir -p "$local_work" "$local_work/tmp"
        export TMPDIR="$local_work/tmp"
        export TMP="$TMPDIR"
        export TEMP="$TMPDIR"
        export _JAVA_OPTIONS="-Djava.io.tmpdir=$TMPDIR"
        mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        java_xmx_gb=$((mem_kb * 75 / 100 / 1024 / 1024))
        if [ "$java_xmx_gb" -lt 4 ]; then
            java_xmx_gb=4
        fi
        echo "Using Java heap: "$java_xmx_gb"G" >&2
        cp -f ${mutect2_vcf} "$local_work/input.mutect2.vcf.gz"
        cp -f ${mutect2_vcf_index} "$local_work/input.mutect2.vcf.gz.tbi"
        cp -f ${mutect2_stats} "$local_work/input.mutect2.vcf.gz.stats"
        cp -f ${read_orientation_model} "$local_work/read-orientation-model.tar.gz"
        cp -f ${contamination_table} "$local_work/contamination.table"
        cp -f ${tumor_segments} "$local_work/segments.table"
        cd "$local_work"

        gatk --java-options "-Djava.io.tmpdir=$TMPDIR -Xmx"$java_xmx_gb"G" FilterMutectCalls \
            -R ${ref_dir}/${fasta} \
            -V input.mutect2.vcf.gz \
            -stats input.mutect2.vcf.gz.stats \
            --orientation-bias-artifact-priors read-orientation-model.tar.gz \
            --contamination-table contamination.table \
            --tumor-segmentation segments.table \
            -O ${filtered_vcf_name}

        gunzip -c ${filtered_vcf_name} | \
        awk 'BEGIN{FS=OFS="\t"} /^#/ || $7 == "PASS"' | \
        bgzip -c > ${pass_vcf_name}

        gatk --java-options "-Djava.io.tmpdir=$TMPDIR" IndexFeatureFile -I ${pass_vcf_name}
        cp -f ${filtered_vcf_name} ${filtered_vcf_name}.tbi ${filtered_vcf_name}.filteringStats.tsv ${pass_vcf_name} ${pass_vcf_name}.tbi "$call_dir"/
    >>>

    output {
        File filtered_vcf = filtered_vcf_name
        File filtered_vcf_index = "${filtered_vcf_name}.tbi"
        File filtering_stats = "${filtered_vcf_name}.filteringStats.tsv"
        File pass_vcf = pass_vcf_name
        File pass_vcf_index = "${pass_vcf_name}.tbi"
    }

    runtime {
        docker: docker_image
        instanceTypes: [cluster_config]
        systemDisk: "cloud " + disk_gb
    }
}
