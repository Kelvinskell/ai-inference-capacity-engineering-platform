# DCGM Prometheus Metrics Reference

## Purpose
Quick reference for interpreting common NVIDIA DCGM metrics in Prometheus for GPU-based LLM workloads.

## Core GPU Health and Utilization

### 1. GPU Utilization
- Metric: `DCGM_FI_DEV_GPU_UTIL`
- Question: How busy is the GPU?

### 2. GPU Memory Used
- Metric: `DCGM_FI_DEV_FB_USED`
- Question: How much VRAM is currently in use?

### 3. GPU Memory Free
- Metric: `DCGM_FI_DEV_FB_FREE`
- Question: How much VRAM remains available?

### 4. GPU Memory Percentage
- Query: `100 * DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE)`
- Question: How full is the GPU memory?

### 5. GPU Temperature
- Metric: `DCGM_FI_DEV_GPU_TEMP`
- Question: Is the GPU running hot?

### 6. Power Usage
- Metric: `DCGM_FI_DEV_POWER_USAGE`
- Question: How much power is the GPU consuming?

### 7. Total Energy Consumption
- Metric: `DCGM_FI_DEV_TOTAL_ENERGY_CONSUMPTION`
- Question: How much energy has the GPU consumed since boot?

### 8. SM Clock
- Metric: `DCGM_FI_DEV_SM_CLOCK`
- Question: What frequency are the compute cores running at?

### 9. Memory Clock
- Metric: `DCGM_FI_DEV_MEM_CLOCK`
- Question: What speed is VRAM running at?

### 10. GPU Utilization (5-Minute Average)
- Query: `avg_over_time(DCGM_FI_DEV_GPU_UTIL[5m])`
- Question: What has utilization looked like recently?

## AI and ML Performance Metrics

### 11. Tensor Core Activity
- Metric: `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE`
- Question: Are Tensor Cores being used?

### 12. DRAM Activity
- Metric: `DCGM_FI_PROF_DRAM_ACTIVE`
- Question: How heavily is GPU memory bandwidth being used?

### 13. Graphics Engine Activity
- Metric: `DCGM_FI_PROF_GR_ENGINE_ACTIVE`
- Question: How active is the graphics or compute engine?

### 14. PCIe TX Throughput
- Metric: `DCGM_FI_PROF_PCIE_TX_BYTES`
- Question: How much data is being sent from the GPU?

### 15. PCIe RX Throughput
- Metric: `DCGM_FI_PROF_PCIE_RX_BYTES`
- Question: How much data is being received by the GPU?

### 16. Memory Copy Utilization
- Metric: `DCGM_FI_DEV_MEM_COPY_UTIL`
- Question: How busy are memory copy engines?

### 17. Average Tensor Usage
- Query: `avg_over_time(DCGM_FI_PROF_PIPE_TENSOR_ACTIVE[5m])`
- Question: How much Tensor Core activity occurred recently?

### 18. Peak GPU Utilization
- Query: `max_over_time(DCGM_FI_DEV_GPU_UTIL[5m])`
- Question: What was the highest utilization in the last 5 minutes?

### 19. Peak VRAM Usage
- Query: `max_over_time(DCGM_FI_DEV_FB_USED[5m])`
- Question: What is the highest memory consumption recently?

### 20. Average Power Draw
- Query: `avg_over_time(DCGM_FI_DEV_POWER_USAGE[5m])`
- Question: What is the average power draw?

## Practical Note
If you understand these metrics first, you will already be much stronger at diagnosing GPU saturation, memory pressure, and reliability issues in AI workloads.
