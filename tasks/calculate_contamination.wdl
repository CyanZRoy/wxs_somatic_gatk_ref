task calculate_contamination {

    File tumor_pileups
    File normal_pileups
    String tumor_sample_name

    String docker_image
    String cluster_config

    String contamination_table_name = "${tumor_sample_name}.contamination.table"
    String tumor_segments_name = "${tumor_sample_name}.segments.table"
    Int raw_disk_gb = ceil(size(tumor_pileups, "GB") + size(normal_pileups, "GB")) + 50
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
        local_work="/tmp/${tumor_sample_name}_contamination"
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
        cp -f ${tumor_pileups} "$local_work/tumor.pileups.table"
        cp -f ${normal_pileups} "$local_work/normal.pileups.table"
        cd "$local_work"

        gatk --java-options "-Djava.io.tmpdir=$TMPDIR -Xmx"$java_xmx_gb"G" CalculateContamination \
            -I tumor.pileups.table \
            -matched normal.pileups.table \
            -O ${contamination_table_name} \
            --tumor-segmentation ${tumor_segments_name}
        cp -f ${contamination_table_name} ${tumor_segments_name} "$call_dir"/
    >>>

    output {
        File contamination_table = contamination_table_name
        File tumor_segments = tumor_segments_name
    }

    runtime {
        docker: docker_image
        instanceTypes: [cluster_config]
        systemDisk: "cloud " + disk_gb
    }
}
