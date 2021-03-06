puts "No of passed arguments passed = $argc"
puts $argv0
create_solution -name simple_conv -dir . -force

# Target a Xilinx FPGA board
add_device -vbnv xilinx:adm-pcie-7v3:1ddr:3.0

set host_args "bin_conv2d.xclbin ../../../../mnist_test_img_0.pgm"
#set host_args "bin_conv2d.xclbin conv"

#set args "bin_conv2d.xclbin ../../../../lena.pgm"
# Host Compiler Flags
set_property -name host_cflags -value "-g -O0 -std=c++0x -I$::env(PWD)" -objects [current_solution]
set ker_name conv_2d_linebuff
#lappend host_args $ker_name
puts $host_args 
# Host source files
add_files "host_app_opt.c"
add_files "pgm.h"
set_property file_type "c header files" [get_files "pgm.h"]
# Kernel Definition
create_kernel $ker_name -type clc
add_files -kernel [get_kernels $ker_name] "conv_opt.cl"


# Define Binary Containers
create_opencl_binary bin_conv2d
set_property region "OCL_REGION_0" [get_opencl_binary bin_conv2d]
create_compute_unit -opencl_binary [get_opencl_binary bin_conv2d] -kernel [get_kernels $ker_name] -name conv0
#set_property max_memory_ports true [get_kernels $ker_name]
# Compile the design for CPU based emulation
compile_emulation -flow cpu
puts "Comipled for CPU emulation..."
run_emulation -flow cpu -args $host_args

# Create estimated resource usage and latency report
report_estimate

# Compile the design for Hardware Emulation
#compile_emulation -flow hardware
#run_emulation -flow hardware -args $args

# Compile the design for execution on the FPGA board
#build_system

# Create the board deployment package for the application
#package_system

