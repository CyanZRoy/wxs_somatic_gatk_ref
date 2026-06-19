task get_pileup_summaries {

    File input_bam
    File input_bam_index
    String sample_id
    File ref_dir
    String variants_for_contamination
    File? intervals_bed
    String interval_padding

    String docker_image
    String cluster_config

    String pileups_table_name = "${sample_id}.pileups.table"
    Int raw_disk_gb = ceil(size(input_bam, "GB") * 2) + 100
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
        local_work="/tmp/${sample_id}_pileups"
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
        cp -f ${input_bam} "$local_work/input.bam"
        cp -f ${input_bam_index} "$local_work/input.bam.bai"
        cp -f ${ref_dir}/${variants_for_contamination} "$local_work/${variants_for_contamination}"
        cp -f ${ref_dir}/${variants_for_contamination}.tbi "$local_work/${variants_for_contamination}.tbi"
        cd "$local_work"

        if [ ${intervals_bed} ]; then
            INTERVAL="-L ${variants_for_contamination} -L ${intervals_bed} --interval-padding ${interval_padding} --interval-set-rule INTERSECTION"
        else
            INTERVAL="-L ${variants_for_contamination}"
        fi

        gatk --java-options "-Djava.io.tmpdir=$TMPDIR -Xmx"$java_xmx_gb"G" GetPileupSummaries \
            -I input.bam \
            -V ${variants_for_contamination} \
            $INTERVAL \
            -O ${pileups_table_name}
        cp -f ${pileups_table_name} "$call_dir"/
    >>>

    output {
        File pileups_table = pileups_table_name
    }

    runtime {
        docker: docker_image
        instanceTypes: [cluster_config]
        systemDisk: "cloud " + disk_gb
    }
}
