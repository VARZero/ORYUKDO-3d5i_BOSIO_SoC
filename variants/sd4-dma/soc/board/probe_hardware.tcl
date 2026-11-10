# Read-only cable/device inventory. No programming or configuration commands.
open_hw_manager
if {[catch {connect_hw_server -url localhost:3121} message]} {
    puts "HARDWARE_SERVER_UNAVAILABLE $message"
} else {
    set targets [get_hw_targets -quiet]
    puts "HARDWARE_TARGET_COUNT [llength $targets]"
    foreach target $targets {
        current_hw_target $target
        if {[catch {open_hw_target} message]} {
            puts "HARDWARE_TARGET_UNAVAILABLE $target $message"
        } else {
            foreach device [get_hw_devices] {puts "HARDWARE_DEVICE $device PART=[get_property PART $device]"}
            close_hw_target
        }
    }
    disconnect_hw_server
}
close_hw_manager
puts "READ_ONLY_HARDWARE_INVENTORY_COMPLETE"
