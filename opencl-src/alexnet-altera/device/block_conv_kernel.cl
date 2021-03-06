#define BLOCK_SIZE	16
#define MAX_KERNEL_SIZE	11
#define K 3
// stride is taken to be 1. If the required stride is not 1, then do conv with stride = 1 and do downsampling.
__kernel
__attribute((reqd_work_group_size(BLOCK_SIZE, BLOCK_SIZE, 1))) 
// TODO:Extend work group in z dimension of 2 dim works to share the same input data.
void block_3d_conv(
	__global float * restrict p_maps,
	__global float * restrict p_weights,
	__global float * restrict p_bias,
	__global float * restrict p_output,
	int no_inputs, int H, int W) {

	// local storage for one block of one input map. Extra rows and columns for padding area.
	__local float map_blk[BLOCK_SIZE + MAX_KERNEL_SIZE - 1][BLOCK_SIZE + MAX_KERNEL_SIZE - 1];
	// local buffer for weights corresponding to 1 map.
	__local float map_ker[MAX_KERNEL_SIZE][MAX_KERNEL_SIZE];

	// output block index of a block of one output map
	int block_x = get_group_id(0);
	int block_y = get_group_id(1);

	// output map pixel offset within block
	int local_x = get_local_id(0);
	int local_y = get_local_id(1);
	// current output map
	int out_map = get_global_id(2);

	// bias unit for this output map which is common to all work items
	__local float local_bias;
   	local_bias = p_bias[out_map];

	// block start location in each input map
	int row_start = block_y * BLOCK_SIZE * W;
	int col_start = block_x * BLOCK_SIZE;

	float sum = 0.0f;
	float zero = 0.0f;
	int filter_start = out_map * K * K * no_inputs;
	const bool copy_ker = ((local_x < K) && (local_y < K));

	// work items in the last column of the block will copy K-1 extra column pixels.
	const bool copy_extra_cols = (local_x == (BLOCK_SIZE-1));
	// first K-1 work items in the last row of the block will copy an extra row of size = BLOCK_SIZE
	const bool copy_extra_row = ((local_y == BLOCK_SIZE-1) && local_x < (K-1));
	int extra_row_idx = BLOCK_SIZE-1 + K - 1 - local_x;
	// NOTE: assuming BLOCK_SIZE > K-1, above two flags will not be true at the same time. 

	for(int imap = 0; imap < no_inputs; imap++) {
		// pointer to this input map in global memory
		global float *p_imap = p_maps + imap * H * W;

		// copy block of input map to local buffer
		//
		// copy one pixel from respective location
		if(copy_extra_row) {
			// copy pixel under this (x,y) location
			map_blk[local_y][local_x] = p_imap[row_start + local_y * W + col_start + local_x];
			// copy extra row assigned to this work item
			#pragma unroll
			for(int p = 0; p < BLOCK_SIZE; p++) {
				map_blk[extra_row_idx][p] = p_imap[row_start + extra_row_idx * W + col_start + p];
			}
		} else if(copy_extra_cols) {
			// copy K-1 extra columns incluidng pixel (x,y) under this work item
			#pragma unroll
			for(int c = 0; c < K; c++) {
				map_blk[local_y][local_x + c] = p_imap[row_start + local_y * W + col_start + local_x + c];
			}
		} else {
			// this work item only need to copy pixel (x,y) which is under its own position.
			map_blk[local_y][local_x] = p_imap[row_start + local_y * W + col_start + local_x];
		}

		// copy kernel for input map
		if(copy_ker) {
			map_ker[local_y][local_x] = p_weights[filter_start + (imap * K + local_y) * K + local_x];
		}

		barrier(CLK_LOCAL_MEM_FENCE);

		// compute
		#pragma unroll
		for(int kr = 0; kr < K; kr++) {
			#pragma unroll
			for(int kc = 0; kc < K; kc++) {
				sum += map_ker[kr][kc] * map_blk[local_y + kr][local_x + kc];
			}
		}	
		// wait for all work items to finish before overwriting local buffer.
		barrier(CLK_LOCAL_MEM_FENCE);
	}
	// add bias unit and write back
	sum += local_bias;
	p_output[(out_map * get_global_size(1) + get_global_id(1)) * get_global_size(0) + get_global_id(0)] = fmax(zero, sum);
}

