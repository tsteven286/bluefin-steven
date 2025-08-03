#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to safely write to sysfs
write_sysfs() {
    if [ -f "$1" ]; then
        echo "$2" | tee "$1" >/dev/null
    else
        echo "Warning: $1 not found, skipping"
    fi
}

# Apply kernel parameters via GRUB
echo "Applying kernel parameters..."
if [ -f /etc/default/grub ]; then
    cp /etc/default/grub /etc/default/grub.bak
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& acpi_cpufreq=+r acpi_pstate_strict=1/' /etc/default/grub
    update-grub
else
    echo "Warning: GRUB config not found, skipping kernel parameters"
fi

# Apply sysctl settings
echo "Applying sysctl settings..."
cat > /etc/sysctl.d/99-performance.conf << EOF
# Custom performance settings
vm.swappiness=10
vm.dirty_ratio=10
vm.dirty_background_ratio=5
net.ipv4.tcp_low_latency=1
net.ipv4.tcp_timestamps=0
net.ipv4.tcp_slow_start_after_idle=0
EOF
sysctl -p /etc/sysctl.d/99-performance.conf

# Apply CPU settings
echo "Applying CPU settings..."
# Set governor (prefer schedutil if available)
GOVERNOR="ondemand"
if [ -d /sys/devices/system/cpu/cpufreq/policy0 ]; then
    if grep -q schedutil /sys/devices/system/cpu/cpufreq/policy0/scaling_available_governors; then
        GOVERNOR="schedutil"
    fi
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq; do
        write_sysfs "$cpu/scaling_governor" "$GOVERNOR"
    done
fi

# Set sampling down factor
write_sysfs "/sys/devices/system/cpu/cpufreq/ondemand/sampling_down_factor" "1000"

# Set energy performance bias
if command_exists x86_energy_perf_policy; then
    x86_energy_perf_policy performance
fi

# Set energy performance preference
for pref in /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference; do
    write_sysfs "$pref" "performance"
done

# Set CPU boost
write_sysfs "/sys/devices/system/cpu/cpufreq/boost" "1"

# Apply ACPI settings
echo "Applying ACPI settings..."
if [ -d /sys/firmware/acpi/platform_profile ]; then
    write_sysfs "/sys/firmware/acpi/platform_profile" "performance"
else
    echo "Warning: ACPI platform_profile not supported"
fi

# Apply audio settings
echo "Applying audio settings..."
# Set audio timeout (Intel HDA audio power saving)
if [ -d /sys/module/snd_hda_intel/parameters ]; then
    write_sysfs "/sys/module/snd_hda_intel/parameters/power_save" "10"
else
    echo "Warning: Audio power saving not supported"
fi

# Apply disk settings
echo "Applying disk settings..."
# Set readahead for sda (modify if using different device)
if [ -b /dev/sda ]; then
    echo "4096" | tee /sys/block/sda/queue/read_ahead_kb >/dev/null
else
    echo "Warning: /dev/sda not found, skipping readahead setting"
fi

# Set elevator scheduler
if command_exists tuned-adm; then
    echo "Setting elevator scheduler via tuned..."
    tuned-adm profile throughput-performance
else
    # Manual elevator setting
    if [ -b /dev/sda ]; then
        echo "kyber" | tee /sys/block/sda/queue/scheduler >/dev/null
    else
        echo "Warning: /dev/sda not found, skipping elevator setting"
    fi
fi

echo "All configurations applied successfully!"
echo "Some changes may require a reboot to take full effect."
