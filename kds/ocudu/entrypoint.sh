"#!/bin/bash
#
# Copyright 2021-2026 Software Radio Systems Limited
#
# By using this file, you agree to the terms and conditions set
# forth in the LICENSE file which can be found at the top level of
# the distribution.
#

# This script updates the gNB configuration file dynamically.
# - Injects cu_up/cu_cp IP overrides when HOSTNETWORK=false or USE_EXT_CORE=true,
#   using POD_IP for bind_addr and LB_IP for ext_addr (if external core is used).
# - If a hal section exists with eal_args, replaces the CPU core list inside @(...)
#   with the CPUs available to the container as read from cgroups (v1/v2),
#   working for both privileged and non-privileged containers.
# - Processes each cell in the ru_ofh section in case the SR-IOV provider is used: 
#   replaces the network_interface field with the corresponding BDF from 
#   PCIDEVICE_<RESOURCE> and updates du_mac_addr using the MAC obtained from dmesg
#   for that BDF.
#
# You can pass the full extended resource name (e.g., \"intel.com/intel_sriov_netdevice\")
# as an environment variable RESOURCE_EXTENDED. The script converts it to the environment
# variable name (e.g., PCIDEVICE_INTEL_COM_INTEL_SRIOV_NETDEVICE) and uses its value for
# processing.
#
# Usage: ./entrypoint.sh /etc/config/gnb-config.yml
# This script has only been tested in containers with Ubuntu 22.04 or higher!

#==============================================================================
# Logging Functions
#==============================================================================

# Log levels
readonly LOG_INFO=\"INFO\"
readonly LOG_WARN=\"WARN\"
readonly LOG_ERROR=\"ERROR\"
readonly LOG_FATAL=\"FATAL\"

log_info() {
    echo \"[$(date +'%Y-%m-%d %H:%M:%S')] [${LOG_INFO}] $*\"
}

log_warn() {
    echo \"[$(date +'%Y-%m-%d %H:%M:%S')] [${LOG_WARN}] $*\" >&2
}

log_error() {
    echo \"[$(date +'%Y-%m-%d %H:%M:%S')] [${LOG_ERROR}] $*\" >&2
}

log_fatal() {
    echo \"[$(date +'%Y-%m-%d %H:%M:%S')] [${LOG_FATAL}] $*\" >&2
    exit 1
}

#==============================================================================
# Validation Functions
#==============================================================================

# Validate required environment variables
validate_environment() {
    local missing=()
    
    # POD_IP is required when HOSTNETWORK=false or USE_EXT_CORE=true
    if [ \"${HOSTNETWORK}\" = \"false\" ] || [ \"${USE_EXT_CORE}\" = \"true\" ]; then
        if [ -z \"${POD_IP}\" ]; then
            missing+=(\"POD_IP\")
        fi
        
        # LB_IP is required when USE_EXT_CORE=true
        if [ \"${USE_EXT_CORE}\" = \"true\" ] && [ -z \"${LB_IP}\" ]; then
            missing+=(\"LB_IP\")
        fi
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error \"Missing required environment variables: ${missing[*]}\"
        return 1
    fi
    
    log_info \"Environment validation passed\"
    return 0
}

# Validate config file exists and is readable
validate_config_file() {
    local config_file=\"$1\"
    
    if [ -z \"$config_file\" ]; then
        log_error \"Config file path not provided\"
        return 1
    fi
    
    if [ ! -f \"$config_file\" ]; then
        log_error \"Config file not found: $config_file\"
        return 1
    fi
    
    if [ ! -r \"$config_file\" ]; then
        log_error \"Config file not readable: $config_file\"
        return 1
    fi
    
    log_info \"Config file validated: $config_file\"
    return 0
}

#==============================================================================
# Utility Functions
#==============================================================================

# Function to convert full extended resource name to environment variable name.
# Example: \"intel.com/intel_sriov_netdevice\" -> \"PCIDEVICE_INTEL_COM_INTEL_SRIOV_NETDEVICE\"
convert_resource_name() {
    local resource_full=\"$1\"
    
    if [ -z \"$resource_full\" ]; then
        log_error \"convert_resource_name: Empty resource name provided\"
        return 1
    fi
    
    # Uppercase the string and replace dots and slashes with underscores.
    local varname
    varname=$(echo \"$resource_full\" | tr '[:lower:]' '[:upper:]' | sed -E 's/[./]/_/g')
    echo \"PCIDEVICE_${varname}\"
    return 0
}

#==============================================================================
# Configuration Manipulation Functions
#==============================================================================

# Update log file paths with timestamps
update_config_paths() {
    local config_file=\"$1\"
    
    if [ -z \"$config_file\" ]; then
        log_error \"update_config_paths: Config file not provided\"
        return 1
    fi
    
    if [ ! -f \"$config_file\" ]; then
        log_error \"update_config_paths: Config file not found: $config_file\"
        return 1
    fi

    local timestamp
    timestamp=$(date +'%Y%m%d-%H%M%S')

    local first_line
    first_line=$(grep -E '^[[:space:]]*[A-Za-z0-9_]*filename:' \"$config_file\" | head -1)
    if [ -z \"$first_line\" ]; then
        log_info \"No filename entries found in config, skipping log path update\" >&2
        return 0
    fi

    local original_path
    original_path=$(echo \"$first_line\" | sed -E 's/^[[:space:]]*[A-Za-z0-9_]*filename:[[:space:]]*(.*)$/\\1/')
    
    local current_dir
    current_dir=$(dirname \"$original_path\")
    
    local ts_candidate base_dir
    ts_candidate=$(basename \"$current_dir\")
    if [[ \"$ts_candidate\" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
        # If a timestamp is present, remove it to get the true base directory.
        base_dir=$(dirname \"$current_dir\")
    else
        base_dir=\"$current_dir\"
    fi

    local new_folder=\"${base_dir}/${timestamp}\"
    
    if ! mkdir -p \"$new_folder\"; then
        log_error \"Failed to create log directory: $new_folder\"
        return 1
    fi
    
    log_info \"Created log directory: $new_folder\" >&2
  
    if ! sed -i -E \"s#([[:space:]]*(filename|[A-Za-z0-9_]+_filename):[[:space:]])${base_dir}(/[0-9]{8}-[0-9]{6})?/#\\1${base_dir}/${timestamp}/#g\" \"$config_file\"; then
        log_error \"Failed to update log paths in config\"
        return 1
    fi

    # Create current symlink
    local symlink_path=\"${base_dir}/current\"
    if [ -L \"$symlink_path\" ]; then
        rm -f \"$symlink_path\"
    fi
    
    if ! ln -sf \"./${timestamp}\" \"${symlink_path}\"; then
        log_warn \"Failed to create symlink: $symlink_path\"
    fi
    
    echo \"$new_folder\"
    return 0
}

# Inject IP overrides for cu_up and cu_cp
inject_ip_overrides() {
    local config_file=\"$1\"
    
    if [ -z \"$config_file\" ]; then
        log_error \"inject_ip_overrides: Config file not provided\"
        return 1
    fi
    
    # In case HOSTNETWORK is set to false, we need to use the Pod's IP as bind_addr. 
    # In case of external core, we need to use the LoadBalancer IP as ext_addr.
    if [ \"${HOSTNETWORK}\" = \"false\" ] || [ \"${USE_EXT_CORE}\" = \"true\" ]; then
        log_info \"Injecting IP overrides (HOSTNETWORK=${HOSTNETWORK}, USE_EXT_CORE=${USE_EXT_CORE})\"
        
        if [ -z \"$POD_IP\" ]; then
            log_error \"POD_IP not set, cannot inject IP overrides\"
            return 1
        fi
        
        if [ \"${USE_EXT_CORE}\" = \"true\" ] && [ -z \"$LB_IP\" ]; then
            log_error \"USE_EXT_CORE=true but LB_IP not set\"
            return 1
        fi
        
        local tmpfile
        tmpfile=$(mktemp) || {
            log_error \"Failed to create temporary file for IP injection\"
            return 1
        }
        
        {
            echo \"cu_up:\"
            echo \"  ngu:\"
            echo \"    socket:\"
            echo \"      - bind_addr: ${POD_IP}\"
            if [ \"${USE_EXT_CORE}\" = \"true\" ]; then
                echo \"        ext_addr: ${LB_IP}\"
            fi
            echo \"cu_cp:\"
            echo \"  amf:\"
            echo \"    bind_addr: ${POD_IP}\"
        } > \"$tmpfile\"
        
        cat \"$config_file\" >> \"$tmpfile\"
        
        if ! mv \"$tmpfile\" \"$config_file\"; then
            log_error \"Failed to inject IP overrides into config\"
            rm -f \"$tmpfile\"
            return 1
        fi
        
        log_info \"Successfully injected IP overrides (POD_IP=${POD_IP})\"
    else
        log_info \"Skipping IP override injection (HOSTNETWORK=${HOSTNETWORK}, USE_EXT_CORE=${USE_EXT_CORE})\"
    fi
    
    return 0
}

#==============================================================================
# Hardware Detection Functions
#==============================================================================

# Detect container-available CPUs from cgroups (v1/v2, privileged/non-privileged)
get_container_cpus() {
    local cpuset=\"\"
    local cgroup_path=\"\"

    if [ -f /proc/self/cgroup ]; then
        cgroup_path=$(grep -E \"cpuset|0::\" /proc/self/cgroup | head -1 | cut -d: -f3)
    fi

    if [ -n \"$cgroup_path\" ] && [ \"$cgroup_path\" != \"/\" ]; then
        if [ -f \"/sys/fs/cgroup/cpuset${cgroup_path}/cpuset.cpus\" ]; then
            cpuset=$(cat \"/sys/fs/cgroup/cpuset${cgroup_path}/cpuset.cpus\")
        elif [ -f \"/sys/fs/cgroup${cgroup_path}/cpuset.cpus\" ]; then
            cpuset=$(cat \"/sys/fs/cgroup${cgroup_path}/cpuset.cpus\")
        fi
    fi

    if [ -z \"$cpuset\" ]; then
        if [ -f /sys/fs/cgroup/cpuset/cpuset.cpus ]; then
            cpuset=$(cat /sys/fs/cgroup/cpuset/cpuset.cpus)
        elif [ -f /sys/fs/cgroup/cpuset.cpus ]; then
            cpuset=$(cat /sys/fs/cgroup/cpuset.cpus)
        fi
    fi

    if [ -z \"$cpuset\" ]; then
        log_warn \"Could not determine CPU set from cgroup, using fallback\"
        if command -v nproc >/dev/null 2>&1; then
            local n
            n=$(nproc)
            if [ \"$n\" -gt 0 ]; then
                cpuset=\"0-$((n-1))\"
            else
                cpuset=\"0-1\"
            fi
        else
            cpuset=\"0-1\"
        fi
    else
        # Log to stderr to avoid polluting the function's echo output
        echo \"[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] Detected CPU set from cgroup: $cpuset\" >&2
    fi

    echo \"$cpuset\" | xargs
    return 0
}

# Update hal.eal_args cores (inside @(...)) only if hal section exists
update_hal_eal_args() {
    local config_file=\"$1\"
    
    if [ -z \"$config_file\" ]; then
        log_error \"update_hal_eal_args: Config file not provided\"
        return 1
    fi

    if ! grep -q \"^[[:space:]]*hal:\" \"$config_file\"; then
        log_info \"No hal section found, skipping eal_args update\"
        return 0
    fi

    if ! grep -q \"^[[:space:]]*eal_args:\" \"$config_file\"; then
        log_info \"No eal_args found, skipping update\"
        return 0
    fi

    local cpus
    cpus=$(get_container_cpus)
    if [ -z \"$cpus\" ]; then
        log_warn \"No CPUs detected, skipping hal.eal_args update\"
        return 0
    fi

    # Replace the CPU list in @(...) or entire pattern (x-y)@(x-y) with detected CPUs
    # Supports both formats: @(cpus) and (lcores)@(cpus)
    if ! sed -i -E \"s/(\\\\([-0-9,]+\\\\))?@\\\\([-0-9,]+\\\\)/(${cpus})@(${cpus})/\" \"$config_file\"; then
        log_error \"Failed to update hal.eal_args\"
        return 1
    fi

    log_info \"Updated hal.eal_args CPU list to: ${cpus}\"
    return 0
}

#==============================================================================
# Network Configuration Functions
#==============================================================================

# Update each cell's network_interface and du_mac_addr using provided BDFs
update_network_interfaces_and_macs() {
    local config_file=\"$1\"
    local device_list=\"$2\"

    if [ -z \"$device_list\" ]; then
        log_info \"No SR-IOV devices provided, skipping network interface update\"
        return 0
    fi

    log_info \"Updating network interfaces for SR-IOV devices: $device_list\"

    IFS=',' read -r -a bdf_array <<< \"$device_list\"
    local tmpfile
    tmpfile=$(mktemp) || {
        log_error \"Failed to create temporary file for network update\"
        return 1
    }
    
    local counter=0
    local current_bdf=\"\"

    while IFS= read -r line || [ -n \"$line\" ]; do
        if echo \"$line\" | grep -qE \"^[[:space:]]*-?[[:space:]]*network_interface:\" && [ $counter -lt ${#bdf_array[@]} ]; then
            current_bdf=$(echo \"${bdf_array[$counter]}\" | xargs)
            indent=$(echo \"$line\" | sed -n 's/^\\([[:space:]]*\\).*/\\1/p')
            # Preserve the dash if it exists (for list syntax), otherwise use plain key
            if echo \"$line\" | grep -qE \"^[[:space:]]*-[[:space:]]*\"; then
                echo \"${indent}- network_interface: $current_bdf\" >> \"$tmpfile\"
            else
                echo \"${indent}network_interface: $current_bdf\" >> \"$tmpfile\"
            fi
            log_info \"Setting network_interface to: $current_bdf\"
        elif echo \"$line\" | grep -q \"^[[:space:]]*du_mac_addr:\" && [ -n \"$current_bdf\" ]; then
            mac=$(dmesg | grep \"$current_bdf\" | grep \"MAC address:\" | tail -n 1 | sed -n 's/.*MAC address: \\([0-9a-fA-F:]\\+\\).*/\\1/p')
            indent=$(echo \"$line\" | sed -n 's/^\\([[:space:]]*\\).*/\\1/p')
            if [ -n \"$mac\" ]; then
                echo \"${indent}du_mac_addr: $mac\" >> \"$tmpfile\"
                log_info \"For BDF $current_bdf, set MAC: $mac\"
            else
                log_warn \"Could not determine MAC for BDF $current_bdf, keeping original\"
                echo \"$line\" >> \"$tmpfile\"
            fi
            counter=$((counter + 1))
            current_bdf=\"\"
        else
            echo \"$line\" >> \"$tmpfile\"
        fi
    done < \"$config_file\"

    if ! mv \"$tmpfile\" \"$config_file\"; then
        log_error \"Failed to update config file with network interfaces\"
        rm -f \"$tmpfile\"
        return 1
    fi

    log_info \"Successfully updated ${counter} network interface(s)\"
    return 0
}

#==============================================================================
# Signal Handling
#==============================================================================

# Handle SIGTERM/SIGINT for graceful shutdown
terminate() {
    log_info \"Received termination signal, forwarding to gNB process\"
    
    local gnb_pid
    gnb_pid=$(pgrep gnb)
    
    if [ -z \"$gnb_pid\" ]; then
        log_warn \"No gNB process found\"
        exit 0
    fi
    
    if ! kill -0 \"$gnb_pid\" 2>/dev/null; then
        log_warn \"gNB process no longer running\"
        exit 0
    fi
    
    log_info \"Sending SIGTERM to gNB (PID: $gnb_pid)\"
    if kill -TERM \"$gnb_pid\"; then
        wait \"$pipe_pid\"
        local exit_code=$?
        log_info \"gNB terminated with exit code $exit_code\"
        exit \"$exit_code\"
    else
        log_error \"Failed to send SIGTERM to gNB\"
        exit 1
    fi
}

#==============================================================================
# Main Execution Functions
#==============================================================================

# Process config and run gNB
process_and_run_gnb() {
    local config_file=\"$1\"
    local updated_config=\"/tmp/gnb-config.yml\"
    
    # Copy config to temp location
    if ! cp \"$config_file\" \"$updated_config\"; then
        log_fatal \"Failed to copy config file to $updated_config\"
    fi
    
    # Apply all config transformations
    inject_ip_overrides \"$updated_config\" || log_fatal \"IP override injection failed\"
    update_hal_eal_args \"$updated_config\" || log_fatal \"HAL EAL args update failed\"
    
    if [ -n \"${DEVICE_LIST}\" ]; then
        update_network_interfaces_and_macs \"$updated_config\" \"${DEVICE_LIST}\" || \\
            log_fatal \"Network interface update failed\"
    fi
    
    log_info \"Configuration processing complete: $updated_config\"
    
    # Run gNB with appropriate logging
    if [ \"$PRESERVE_OLD_LOGS\" = \"true\" ]; then
        local log_path
        log_path=$(update_config_paths \"$updated_config\") || log_fatal \"Log path setup failed\"
        
        log_info \"Starting gNB with log preservation in: $log_path\"
        {
            gnb -c \"$updated_config\" 2>&1 | tee -a \"${log_path}/gnb.stdout\"
            exit ${PIPESTATUS[0]}
        } &
    else
        log_info \"Starting gNB (logs not preserved)\"
        gnb -c \"$updated_config\" &
    fi
    
    pipe_pid=$!
    wait \"$pipe_pid\"
    local exit_code=$?
    
    log_info \"gNB exited with code $exit_code\"
    return $exit_code
}

# Main entry point
main() {
    # Parse arguments
    local config_file=\"$1\"
    
    if [ -z \"$config_file\" ]; then
        log_fatal \"Usage: $0 <config_file>\"
    fi
    
    # Initialize
    log_info \"=== OCUDU gNB Entrypoint Script ===\"
    log_info \"Config file: $config_file\"
    log_info \"ENABLE_OCUDU_O1: ${ENABLE_OCUDU_O1}\"
    log_info \"PRESERVE_OLD_LOGS: ${PRESERVE_OLD_LOGS}\"
    log_info \"HOSTNETWORK: ${HOSTNETWORK}\"
    log_info \"USE_EXT_CORE: ${USE_EXT_CORE}\"
    
    # Setup signal handling
    trap terminate SIGTERM SIGINT
    
    # Validate environment (only if needed)
    if [ \"${HOSTNETWORK}\" = \"false\" ] || [ \"${USE_EXT_CORE}\" = \"true\" ]; then
        validate_environment || log_fatal \"Environment validation failed\"
    fi
    
    # Setup resource variables
    local resource_extended=\"${RESOURCE_EXTENDED:-intel.com/intel_sriov_netdevice}\"
    local resource_var
    resource_var=$(convert_resource_name \"$resource_extended\") || log_fatal \"Resource name conversion failed\"
    log_info \"Using SR-IOV resource: $resource_extended (env: $resource_var)\"
    
    DEVICE_LIST=\"${!resource_var}\"
    if [ -n \"$DEVICE_LIST\" ]; then
        log_info \"SR-IOV devices detected: $DEVICE_LIST\"
    else
        log_info \"No SR-IOV devices detected\"
    fi
    
    # Main loop
    while true; do
        # Wait for O1 config if enabled
        if [ \"$ENABLE_OCUDU_O1\" = \"true\" ]; then
            log_info \"O1 enabled, waiting for config file creation\"
            local elapsed=0
            local timeout=\"${CONFIG_CREATE_TIMEOUT}\"
            
            while [ ! -f \"$config_file\" ] && [ $elapsed -lt \"$timeout\" ]; do
                log_info \"Waiting for O1 to create config... (${elapsed}/${timeout}s)\"
                sleep 1
                elapsed=$((elapsed + 1))
            done
            
            if [ ! -f \"$config_file\" ]; then
                log_fatal \"Timeout after ${timeout}s waiting for config: $config_file\"
            fi
            
            log_info \"Config file created by O1\"
        fi
        
        # Validate config exists
        validate_config_file \"$config_file\" || log_fatal \"Config validation failed\"
        
        # Validate SR-IOV HAL configuration
        if [ -n \"$DEVICE_LIST\" ]; then
            # Validate that HAL eal_args are present when using SR-IOV
            if ! grep -q \"^[[:space:]]*hal:\" \"$config_file\"; then
                log_fatal \"SR-IOV devices detected but no 'hal' section found in config. When using SR-IOV, the gNB config MUST include 'hal.eal_args' for DPDK configuration.\"
            fi

            if ! grep -q \"^[[:space:]]*eal_args:\" \"$config_file\"; then
                log_fatal \"SR-IOV devices detected but 'hal.eal_args' not found in config. When using SR-IOV, the gNB config MUST include 'hal.eal_args' for DPDK configuration.\"
            fi

            log_info \"SR-IOV HAL configuration validated\"
        fi

        # Process config and run gNB
        process_and_run_gnb \"$config_file\"
        local exit_code=$?
        
        # Handle exit
        if [ $exit_code -ne 0 ]; then
            log_error \"gNB failed with exit code $exit_code\"
            exit $exit_code
        fi
        
        # Clean up O1 config for next iteration
        if [ \"$ENABLE_OCUDU_O1\" = \"true\" ] && [ -f \"$config_file\" ]; then
            log_info \"Removing O1 config for next iteration\"
            rm -f \"$config_file\"
        fi
        
        log_info \"gNB exited cleanly, restarting...\"
    done
}

#==============================================================================
# Script Initialization
#==============================================================================

# Exit on error, undefined vars, pipe failures (disabled for now to maintain compatibility)
# set -euo pipefail

# Set defaults
PRESERVE_OLD_LOGS=\"${PRESERVE_OLD_LOGS:-false}\"
CONFIG_CREATE_TIMEOUT=\"${CONFIG_CREATE_TIMEOUT:-30}\"
ENABLE_OCUDU_O1=\"${ENABLE_OCUDU_O1:-false}\"
HOSTNETWORK=\"${HOSTNETWORK:-true}\"
USE_EXT_CORE=\"${USE_EXT_CORE:-false}\"

# Run main
main \"$@\"
"
