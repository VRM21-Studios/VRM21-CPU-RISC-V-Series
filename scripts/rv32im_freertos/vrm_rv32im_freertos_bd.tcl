# ============================================================================
# VRM21 Studios - VRM21-CPU-RISC-V-Series
#
# Script      : scripts/rv32im_freertos/vrm_rv32im_freertos_bd.tcl
# Target      : Kria KR260 (K26 SOM, xck26-sfvc784-2LV-c), Vivado 2025.2
# Purpose     : Create the block design RV32IM_VCF for the rv32im_freertos
#               variant:
#                 vrm_soc_axi_0 (bootloader + RV32IM CPU + VCF, BOOT_FREERTOS=1)
#                 axi_dma_0     (simple mode: MM2S -> s_axis, m_axis -> S2MM)
#                 axi_gpio_0    (31 outputs -> ext_irq_in: CLEAR and FX presets)
#
# Run (Vivado Tcl console):
#   source <repo>/scripts/rv32im_freertos/vrm_rv32im_freertos_bd.tcl
#     - no project open: creates PROJ_NAME under PROJ_DIR (KR260 board)
#     - a project open : adds the sources and the BD to that project
#   Then check the BD and the Address Editor and run Generate Bitstream.
#   Export RV32IM_VCF.bit (renamed from RV32IM_VCF_wrapper.bit) together with
#   RV32IM_VCF.hwh from .gen/sources_1/bd/RV32IM_VCF/hw_handoff.
#
# Layout (resolved relative to this script):
#   rtl/rv32im_freertos/*.v, include/rv32im_freertos/vrm_soc_map_rv32i.vh,
#   include/rv32im_freertos/firmware.mem (FreeRTOS autoboot image, <= 16 KiB).
#   Settings can be overridden in an ignored file next to this script:
#   scripts/rv32im_freertos/local_settings.tcl (for example PROJ_DIR).
#
# STREAM MAP (all clocks pl_clk0 = 100 MHz, one reset; the firmware tick
# assumes 100 MHz)
#   axi_dma_0 M_AXIS_MM2S -> vrm_soc_axi_0 s_axis  (32-bit {R,L} stereo)
#   vrm_soc_axi_0 m_axis  -> axi_dma_0 S_AXIS_S2MM
#   axi_gpio_0 gpio_io_o[30:0] -> vrm_soc_axi_0 ext_irq_in[30:0]
#     (bit 0 = CLEAR, bits 1..6 = FX presets; edge triggered)
#   cpu_halt / cpu_pc / debug_reg_x1 are left open.
#
# PS VIEW (M_AXI_HPM0_FPD)
#   vrm_soc_axi_0/s_axi : 0x4_0000_0000, range 4G. The IP decodes the offset:
#                         RAM 0x1000_0000-0x1000_FFFF, CPU_CTRL 0x0000_C000,
#                         VCF 0x8000_2000.
#   axi_dma_0/S_AXI_LITE and axi_gpio_0/S_AXI : automatic addresses.
#
# DDR / ADDRESS NOTES
#   HP0 = DMA MM2S, HP1 = DMA S2MM, 128 bit, one SmartConnect each.
#   DMA address width 32: DMA buffers below 4 GB (DDR_LOW only).
#   PL-to-PS interrupts are off; the host polls.
#
# Status: this script reproduces the block design configuration that was
# implemented and tested on the KR260 (see docs/rv32im_freertos/06_validation.md).
# ============================================================================

# ---------------------------------------------------------------- settings
# Paths are resolved from the location of this file, so it must be sourced.
if {[info script] eq ""} {
    error "run this file with: source <repo>/scripts/rv32im_freertos/vrm_rv32im_freertos_bd.tcl\
 (pasted into the console, the script cannot locate the repository)"
}
set SCRIPT_DIR [file dirname [file normalize [info script]]]
set REPO_DIR   [file normalize [file join $SCRIPT_DIR .. ..]]
set SRC_DIR    [file join $REPO_DIR rtl rv32im_freertos]
set INC_DIR    [file join $REPO_DIR include rv32im_freertos]
set PROJ_NAME  "rv32im_freertos"
set PROJ_DIR   [file join $REPO_DIR build vivado_rv32im_freertos]
set BD_NAME    "RV32IM_VCF"
set PART       "xck26-sfvc784-2LV-c"
set PL_CLK_MHZ 100
set GPIO_WIDTH 31
set BOOT_MAX_BYTES 16384
# Glob patterns of projects that must never be modified by this script.
set FROZEN {}

set local_settings [file join $SCRIPT_DIR local_settings.tcl]
if {[file exists $local_settings]} { source $local_settings }

foreach pat $FROZEN {
    foreach v [list $PROJ_DIR $SRC_DIR $INC_DIR] {
        if {[string match $pat $v]} { error "frozen project path ($pat): $v" }
    }
}

# every file the top vrm_soc_axi needs (checked with xvlog/xelab), nothing else
set RTL_FILES {
    vrm_alu.v vrm_mdu.v vrm_csr.v vrm_cpu_rv32im_core.v vrm_cpu_rv32im_wrapper.v
    vrm_timer.v vrm_irq_arbiter.v vrm_vcf_core.v vrm_vcf_mmio.v
    vrm_bootloader.v vrm_soc_top.v vrm_soc_axi.v
}
set HDR_FILE  [file join $INC_DIR vrm_soc_map_rv32i.vh]
set MEM_FILE  [file join $INC_DIR firmware.mem]

# ---------------------------------------------------------------- source checks
set missing {}
foreach f $RTL_FILES {
    if {![file exists [file join $SRC_DIR $f]]} { lappend missing $f }
}
foreach p [list $HDR_FILE $MEM_FILE] {
    if {![file exists $p]} { lappend missing $p }
}
if {[llength $missing] > 0} { error "missing source files: $missing" }
set unknown {}
foreach p [glob -nocomplain -directory $SRC_DIR *.v] {
    if {[lsearch -exact $RTL_FILES [file tail $p]] < 0} { lappend unknown [file tail $p] }
}
if {[llength $unknown] > 0} {
    error "RTL files in $SRC_DIR not listed in RTL_FILES: $unknown"
}

# boot image size: byte count of a $readmemh byte file (objcopy -O verilog)
proc mem_extent {path} {
    set fh [open $path r]
    set addr 0
    set top 0
    set first {}
    while {[gets $fh line] >= 0} {
        set line [string trim $line]
        if {$line eq ""} { continue }
        if {[string index $line 0] eq "@"} {
            scan [string range $line 1 end] %x addr
            continue
        }
        foreach tok [split [regsub -all {\s+} $line " "] " "] {
            if {$tok eq ""} { continue }
            if {[llength $first] < 4} { lappend first [string toupper $tok] }
            incr addr
            if {$addr > $top} { set top $addr }
        }
    }
    close $fh
    return [list $top $first]
}
lassign [mem_extent $MEM_FILE] mem_bytes mem_first
if {$mem_bytes > $BOOT_MAX_BYTES} {
    error "$MEM_FILE holds $mem_bytes bytes; the autoboot slot is $BOOT_MAX_BYTES bytes"
}
if {$mem_first ne {73 10 40 30}} {
    puts "WARNING: $MEM_FILE does not start with the FreeRTOS startup word (csrw mie, zero): $mem_first"
}
puts "INFO: boot image $MEM_FILE, $mem_bytes bytes"

# ---------------------------------------------------------------- project
if {[catch {current_project} cur_proj]} {
    create_project $PROJ_NAME $PROJ_DIR -part $PART
    set bparts [lsort [get_board_parts -quiet *kr260_som*]]
    if {[llength $bparts] == 0} {
        error "KR260 board files not found (install the Kria board files first)"
    }
    set_property board_part [lindex $bparts end] [current_project]
    catch {set_property board_connections {som240_1_connector xilinx.com:kr260_carrier:som240_1_connector:1.0 som240_2_connector xilinx.com:kr260_carrier:som240_2_connector:1.0} [current_project]}
    puts "INFO: project $PROJ_NAME created, board [get_property board_part [current_project]]"
}
foreach pat $FROZEN {
    if {[string match $pat [get_property DIRECTORY [current_project]]]} {
        error "the open project is frozen ($pat)"
    }
}

set want [concat [lmap f $RTL_FILES {file normalize [file join $SRC_DIR $f]}] \
                 [list [file normalize $HDR_FILE] [file normalize $MEM_FILE]]]
foreach p $want {
    if {[llength [get_files -quiet -of_objects [get_filesets sources_1] $p]] > 0} { continue }
    set in_sim [get_files -quiet -of_objects [get_filesets sim_1] $p]
    if {[llength $in_sim] > 0} {
        move_files -fileset sources_1 $in_sim
    } else {
        add_files -fileset sources_1 -norecurse $p
    }
}
set_property file_type {Verilog Header} [get_files -of_objects [get_filesets sources_1] [file normalize $HDR_FILE]]
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sources_1] [file normalize $MEM_FILE]]

# only one firmware.mem may reach $readmemh in synthesis
foreach f [get_files -quiet -of_objects [get_filesets sources_1] -filter {NAME =~ "*firmware.mem"}] {
    if {[file normalize $f] ne [file normalize $MEM_FILE]} {
        remove_files -fileset sources_1 $f
        puts "INFO: removed from sources_1 (file kept on disk): $f"
    }
}

set inc [get_property include_dirs [get_filesets sources_1]]
if {[lsearch -exact $inc $INC_DIR] < 0} {
    lappend inc $INC_DIR
    set_property include_dirs $inc [get_filesets sources_1]
}
update_compile_order -fileset sources_1

# ============================================================================
# BLOCK DESIGN
#   1  PS + block automation (KR260 board preset)
#   2  PS: pl_clk0 100 MHz; pl_clk1, HPM1, HPM0_LPD, PL-to-PS irq off
#   3  PS: S_AXI_HP0 (DMA read), S_AXI_HP1 (DMA write), 128 bit
#   4  AXI DMA (simple mode) and AXI GPIO
#   5  module reference vrm_soc_axi (cache removed, interfaces checked)
#   6  AXI-Stream and GPIO wiring
#   7  explicit clock and reset before automation
#   8  connection automation for the AXI-Lite slaves, clocking-wizard check
#   9  DDR side, one SmartConnect per HP port
#  10  remaining clock / reset pins, addresses, validate, wrapper
# ============================================================================
if {[llength [get_files -quiet ${BD_NAME}.bd]] > 0} {
    error "block design $BD_NAME already exists: remove it (and its wrapper) or change BD_NAME"
}
create_bd_design $BD_NAME
current_bd_design $BD_NAME

proc need_pin {p} {
    set o [get_bd_pins -quiet $p]
    if {$o eq ""} { error "pin not found: $p" }
    return $o
}
proc need_intf {p} {
    set o [get_bd_intf_pins -quiet $p]
    if {$o eq ""} { error "interface pin not found: $p" }
    return $o
}

# ---- 1. PS + block automation
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e zynq_ultra_ps_e_0]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} $ps

# ---- 2 + 3. PS configuration
set_property -dict [list \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ $PL_CLK_MHZ \
    CONFIG.PSU__FPGA_PL1_ENABLE {0} \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__USE__IRQ0 {0} \
    CONFIG.PSU__USE__IRQ1 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} \
    CONFIG.PSU__SAXIGP2__DATA_WIDTH {128} \
    CONFIG.PSU__USE__S_AXI_GP3 {1} \
    CONFIG.PSU__SAXIGP3__DATA_WIDTH {128} \
] $ps

# ---- 4. AXI DMA (simple mode) and AXI GPIO
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma axi_dma_0]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_micro_dma {0} \
    CONFIG.c_sg_length_width {26} \
    CONFIG.c_addr_width {32} \
    CONFIG.c_m_axi_mm2s_data_width {32} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_m_axi_s2mm_data_width {32} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_mm2s_burst_size {16} \
    CONFIG.c_s2mm_burst_size {16} \
] $dma
set gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio axi_gpio_0]
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH $GPIO_WIDTH \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_IS_DUAL {0} \
    CONFIG.C_DOUT_DEFAULT {0x00000000} \
] $gpio

# ---- 5. RTL module reference
# Vivado caches the interface definition under <project>.gen/sources_1/bd/mref
# and may reuse it after a port change; the BD is new, so remove the leftover.
set mref_dir [file join [get_property DIRECTORY [current_project]] "[get_property NAME [current_project]].gen" sources_1 bd mref vrm_soc_axi]
if {[file exists $mref_dir]} { file delete -force $mref_dir; puts "INFO: removed module-reference cache $mref_dir" }
create_bd_cell -type module -reference vrm_soc_axi vrm_soc_axi_0
set want_intf {s_axi s_axis m_axis}
set miss [lmap n $want_intf {expr {[llength [get_bd_intf_pins -quiet vrm_soc_axi_0/$n]] ? [continue] : $n}}]
if {[llength $miss] > 0} {
    catch {update_module_reference [get_bd_cells vrm_soc_axi_0]}
    set miss [lmap n $want_intf {expr {[llength [get_bd_intf_pins -quiet vrm_soc_axi_0/$n]] ? [continue] : $n}}]
}
if {[llength $miss] > 0} {
    set found [lsort [get_property NAME [get_bd_intf_pins -quiet vrm_soc_axi_0/*]]]
    error "vrm_soc_axi_0 lacks interfaces $miss (found: $found); check RTL_FILES, reopen the project, delete the BD and run again"
}

# ---- 6. AXI-Stream and GPIO wiring
connect_bd_intf_net [need_intf axi_dma_0/M_AXIS_MM2S] [need_intf vrm_soc_axi_0/s_axis]
connect_bd_intf_net [need_intf vrm_soc_axi_0/m_axis] [need_intf axi_dma_0/S_AXIS_S2MM]

set gp [need_pin axi_gpio_0/gpio_io_o]
set ip [need_pin vrm_soc_axi_0/ext_irq_in]
set gw [expr {[get_property LEFT $gp] - [get_property RIGHT $gp] + 1}]
set iw [expr {[get_property LEFT $ip] - [get_property RIGHT $ip] + 1}]
if {$gw != $iw} { error "axi_gpio_0/gpio_io_o is $gw bits, vrm_soc_axi_0/ext_irq_in is $iw bits" }
connect_bd_net $gp $ip

# ---- 7. explicit clock and reset before automation
set clk [need_pin zynq_ultra_ps_e_0/pl_clk0]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_pl_clk0
connect_bd_net $clk [need_pin rst_pl_clk0/slowest_sync_clk]
connect_bd_net [need_pin zynq_ultra_ps_e_0/pl_resetn0] [need_pin rst_pl_clk0/ext_reset_in]
set rstn [need_pin rst_pl_clk0/peripheral_aresetn]

proc tie {src p} {
    set pin [need_pin $p]
    if {[llength [get_bd_nets -quiet -of_objects $pin]] == 0} { connect_bd_net $src $pin }
}
foreach p {vrm_soc_axi_0/s_axi_aclk
           axi_dma_0/s_axi_lite_aclk axi_dma_0/m_axi_mm2s_aclk axi_dma_0/m_axi_s2mm_aclk
           axi_gpio_0/s_axi_aclk
           zynq_ultra_ps_e_0/maxihpm0_fpd_aclk
           zynq_ultra_ps_e_0/saxihp0_fpd_aclk zynq_ultra_ps_e_0/saxihp1_fpd_aclk} {
    tie $clk $p
}
foreach p {vrm_soc_axi_0/s_axi_aresetn axi_dma_0/axi_resetn axi_gpio_0/s_axi_aresetn} {
    tie $rstn $p
}

# ---- 8. connection automation (AXI-Lite slaves -> M_AXI_HPM0_FPD)
foreach s {vrm_soc_axi_0/s_axi axi_dma_0/S_AXI_LITE axi_gpio_0/S_AXI} {
    need_intf $s
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list \
        Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} \
        Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} Slave /$s \
        ddr_seg {Auto} intc_ip {Auto} master_apm {0}] [get_bd_intf_pins $s]
}
if {[llength [get_bd_cells -quiet -filter {VLNV =~ "*clk_wiz*"}]] > 0} {
    error "automation created a clocking wizard; delete the BD, check that every clock pin is connected before automation, and run again"
}

# ---- 9. DDR side: one SmartConnect per HP port
proc hp_smc {name hp masters} {
    upvar clk clk rstn rstn
    set smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect $name]
    set_property -dict [list CONFIG.NUM_SI [llength $masters] CONFIG.NUM_MI {1}] $smc
    connect_bd_net $clk  [need_pin $name/aclk]
    connect_bd_net $rstn [need_pin $name/aresetn]
    set i 0
    foreach m $masters {
        connect_bd_intf_net [need_intf $m] [need_intf $name/[format "S%02d_AXI" $i]]
        incr i
    }
    connect_bd_intf_net [need_intf $name/M00_AXI] [need_intf zynq_ultra_ps_e_0/S_AXI_${hp}_FPD]
}
hp_smc axi_smc_hp0 HP0 {axi_dma_0/M_AXI_MM2S}
hp_smc axi_smc_hp1 HP1 {axi_dma_0/M_AXI_S2MM}

# ---- 10. remaining clock / reset pins (not the reset block itself)
foreach cell [get_bd_cells -quiet] {
    if {[string match "*proc_sys_reset*" [get_property VLNV $cell]]} { continue }
    foreach pin [get_bd_pins -quiet -of_objects $cell -filter {TYPE == clk && DIR == I}] {
        if {[llength [get_bd_nets -quiet -of_objects $pin]] == 0} { connect_bd_net $clk $pin }
    }
    if {$cell eq [get_bd_cells zynq_ultra_ps_e_0]} { continue }
    foreach pin [get_bd_pins -quiet -of_objects $cell -filter {TYPE == rst && DIR == I}] {
        if {[llength [get_bd_nets -quiet -of_objects $pin]] == 0} { connect_bd_net $rstn $pin }
    }
}

# ---- addresses
assign_bd_address

proc to_bytes {v} {
    set v [string trim $v]
    if {[regexp -nocase {^([0-9]+)\s*([KMG])$} $v -> n u]} {
        return [expr {wide($n) * [dict get {K 1024 M 1048576 G 1073741824} [string toupper $u]]}]
    }
    return [expr {wide($v)}]
}
proc ps_seg {inst} {
    get_bd_addr_segs -quiet -of_objects [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] -filter "NAME =~ \"*${inst}*\""
}

# vrm_soc_axi_0 decodes absolute offsets up to 0x8000_2000, so it needs a
# 4 GB window aligned to 4 GB (HPM0_FPD high aperture). One slave, so no
# segment-name collision.
set soc_seg [ps_seg vrm_soc_axi_0]
if {[llength $soc_seg] != 1} { error "vrm_soc_axi_0/s_axi: expected one PS segment, found: $soc_seg" }
set SOC_RANGE  [expr {wide(1) << 32}]
set SOC_OFFSET [expr {wide(0x400000000)}]
if {[to_bytes [get_property RANGE $soc_seg]] != $SOC_RANGE || [to_bytes [get_property OFFSET $soc_seg]] != $SOC_OFFSET} {
    set_property range 4G $soc_seg
    set_property offset 0x000400000000 $soc_seg
}
foreach {inst min} {vrm_soc_axi_0 4294967296 axi_dma_0 4096 axi_gpio_0 4096} {
    set seg [ps_seg $inst]
    if {[llength $seg] != 1} { error "$inst: expected one PS segment, found: $seg" }
    puts "INFO: PS -> $inst @ [get_property OFFSET $seg] range [get_property RANGE $seg]"
    if {[to_bytes [get_property RANGE $seg]] < $min} { error "$inst range is below $min bytes" }
}

# 32-bit DMA masters: keep only DDR_LOW (BD 41-1743 for DDR_HIGH is expected)
foreach sp {axi_dma_0/Data_MM2S axi_dma_0/Data_S2MM} {
    set spc [get_bd_addr_spaces -quiet $sp]
    if {$spc eq ""} { error "address space not found: $sp" }
    set low 0
    foreach seg [get_bd_addr_segs -quiet -of_objects $spc] {
        if {[string match "*DDR_LOW*" [get_property NAME $seg]]} { incr low } else { catch {exclude_bd_addr_seg $seg} }
    }
    if {$low == 0} { error "$sp has no DDR_LOW segment" }
}

regenerate_bd_layout
validate_bd_design
save_bd_design

set wrap [make_wrapper -files [get_files ${BD_NAME}.bd] -top]
if {$wrap ne "" && [file exists $wrap]} {
    add_files -norecurse $wrap
    set_property top ${BD_NAME}_wrapper [current_fileset]
    update_compile_order -fileset sources_1
    puts "INFO: top = ${BD_NAME}_wrapper"
} else {
    puts "WARNING: wrapper not found, create it from the Sources tab (Create HDL Wrapper)"
}
puts "INFO: $BD_NAME done. Check the Address Editor: vrm_soc_axi_0 at 0x4_0000_0000 / 4G, DMA masters DDR_LOW only."
