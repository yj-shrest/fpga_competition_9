# FPGA GNN Accelerator

A hardware implementation of a **Graph Neural Network (GNN)** accelerator written in Verilog, targeting FPGA devices. The design encodes edge and node features through multi-layer perceptrons (MLPs), performs iterative message passing across 8 graph-processing blocks, and decodes the final edge representations into scalar attention scores.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Pipeline Phases](#pipeline-phases)
- [Module Hierarchy](#module-hierarchy)
- [Key Parameters](#key-parameters)
- [Memory Files](#memory-files)
- [Weight Files (.mif)](#weight-files-mif)
- [Simulation](#simulation)
- [File Structure](#file-structure)

---

## Architecture Overview

```
 ┌─────────────────────────────────────────────────────────────────────┐
 │                         top_module                                  │
 │                                                                     │
 │  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────┐   │
 │  │ Edge Encoder │   │ Node Encoder │   │  Message Passing     │   │
 │  │  (3-layer    │   │  (3-layer    │   │  Wrapper             │   │
 │  │   MLP)       │   │   MLP)       │   │  (8 MP blocks)       │   │
 │  │              │   │              │   │                      │   │
 │  │  6→32 feats  │   │  6→32 feats  │   │  ┌───────────────┐  │   │
 │  └──────┬───────┘   └──────┬───────┘   │  │ Edge Network  │  │   │
 │         │                  │           │  │ (3-layer MLP) │  │   │
 │         ▼                  ▼           │  └───────────────┘  │   │
 │  ┌─────────────────────────────────┐   │  ┌───────────────┐  │   │
 │  │         storage_module          │◄──┤  │ Node Network  │  │   │
 │  │  (BRAMs for encoder outputs,    │   │  │ (3-layer MLP) │  │   │
 │  │   ping-pong buffers,            │   │  └───────────────┘  │   │
 │  │   scatter-sum buffers,          │   └──────────────────────┘   │
 │  │   connectivity BRAMs,           │            │                  │
 │  │   edge-score BRAM)              │            ▼                  │
 │  └─────────────────────────────────┘   ┌──────────────┐           │
 │                                        │ Edge Decoder │           │
 │                                        │ (3-layer MLP │           │
 │                                        │  → 1 score)  │           │
 │                                        └──────────────┘           │
 └─────────────────────────────────────────────────────────────────────┘
```

The graph connectivity is fixed at elaboration time via `.mem` files. The learned weights are loaded from `.mif` files at simulation start.

---

## Pipeline Phases

The top-level FSM (`top_module`) sequences work through the following phases:

| Phase | ID | Description |
|-------|----|-------------|
| `IDLE` | 0 | Waiting for external start trigger |
| `EDGE_ENCODE` | 1 | Run the Edge Encoder |
| `EDGE_ENCODE_WAIT` | 2 | Wait for Edge Encoder `done` |
| `NODE_ENCODE` | 3 | Run the Node Encoder |
| `NODE_ENCODE_WAIT` | 4 | Wait for Node Encoder `done` |
| `MESSAGE_PASSING` | 5 | Run 8 Message-Passing blocks sequentially |
| `MESSAGE_PASSING_WAIT` | 6 | Wait for Message-Passing `done` |
| `EDGE_DECODE` | 7 | Run the Edge Decoder |
| `EDGE_DECODE_WAIT` | 8 | Wait for Edge Decoder `done` |
| `DONE` | 9 | Processing complete; `processing_done` asserted |

---

## Module Hierarchy

```
top_module
├── edge_encoder               – Encodes each edge (6→32 features)
│   ├── edge_encoder_layer_1   – MLP layer 1  (6  → 32 neurons)
│   ├── edge_encoder_layer_2   – MLP layer 2  (32 → 32 neurons)
│   └── edge_encoder_layer_3   – MLP layer 3  (32 → 32 neurons)
│
├── node_encoder               – Encodes each node (6→32 features)
│   ├── node_encoder_layer_1   – MLP layer 1  (6  → 32 neurons)
│   ├── node_encoder_layer_2   – MLP layer 2  (32 → 32 neurons)
│   └── node_encoder_layer_3   – MLP layer 3  (32 → 32 neurons)
│
├── storage_module             – Central BRAM storage
│   ├── bram_burst_wrapper     – Burst R/W wrapper (encoder BRAMs, ping-pong)
│   ├── bram_dual              – Simple dual-port BRAM (connectivity)
│   └── bram_burst_wrapper_ss  – Scatter-sum variant of burst wrapper
│
├── message_passing_wrapper    – Sequences 8 MP blocks
│   └── Message_Passing [×8]   – One block per GNN iteration
│       ├── Edge_Network       – Updates edge features
│       │   └── MP_Edge_Layer_B{n}_L{1,2,3}  (192→32 neurons)
│       └── Node_Network       – Updates node features
│           └── MP_Node_Layer_B{n}_L{1,2,3}  (96→32 neurons)
│
└── edge_decoder               – Decodes final edge features → scalar score
    ├── Edge_Decoder_Layer     – MLP layers 1 & 2  (32→32)
    └── Edge_Output_Transform  – Output layer      (32→1)
```

### Primitive modules (shared across all MLPs)

| Module | Purpose |
|--------|---------|
| `neuron` | Single neuron: loads weights/bias from `.mif` files, performs MAC |
| `multiplier` | Pipelined signed multiply |
| `adder` | Pipelined signed accumulator |
| `ReLu` | Activation function + bias add |
| `register` | Mux that selects one element from a flattened array |
| `counter` | Counts from 1 to `END_COUNTER`, used to step through MAC cycles |
| `counter_with_enable` | Counter with external enable |

---

## Key Parameters

All parameters are declared in `top_module` and propagated downwards:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM_EDGES` | 4 | Number of edges in the graph |
| `NUM_NODES` | 5 | Number of nodes in the graph |
| `NUM_FEATURES` | 6 | Initial feature dimensionality for both edges and nodes |
| `OUT_FEATURES` | 32 | Encoded feature dimensionality (output of encoders and MP layers) |
| `DATA_BITS` | 8 | Bit width of data words |
| `ADDR_BITS` | 14 | BRAM address width for edge storage |
| `NODE_ADDR_BITS` | 18 | BRAM address width for node storage |
| `MAX_BURST_SIZE` | 32 | Maximum burst length for BRAM wrappers |

The message-passing layer input widths follow from the above:
- **Edge Network input**: `(EDGE_FEATURES + NODE_FEATURES + NODE_FEATURES) × DATA_BITS`  = 192 bits (concatenation of edge, source-node, and destination-node features)
- **Node Network input**: `(NODE_FEATURES + NODE_FEATURES) × DATA_BITS` = 96 bits (concatenation of node and scatter-sum features; first block also uses initial features)

---

## Memory Files

The following binary (base-2) `.mem` files must be present in the working directory at simulation time:

| File | Content |
|------|---------|
| `mem_files/edge_initial_features.mem` | Initial edge feature vectors (one word per line) |
| `mem_files/node_initial_features.mem` | Initial node feature vectors (one word per line) |
| `mem_files/connectivity_source_data.mem` | Source node index for each edge |
| `mem_files/connectivity_destination_data.mem` | Destination node index for each edge |
| `mem_files/scatter_sum_in.mem` | Initial scatter-sum accumulator (all zeros) |

Example graph (4 edges, 5 nodes):

```
Edge 0: Node 1 → Node 2
Edge 1: Node 2 → Node 3
Edge 2: Node 1 → Node 3
Edge 3: Node 1 → Node 4
```

---

## Weight Files (.mif)

Neural-network weights and biases are stored in binary `.mif` files (one value per line, MSB first). They are loaded at simulation start via `$readmemb`. The `.mif` extension is listed in `.gitignore` so the files must be generated separately using the training script.

Naming convention:

| Layer type | Weight file | Bias file |
|------------|-------------|-----------|
| Edge encoder, layer `L`, neuron `N` | `edge_encoder_w_L_N.mif` | `edge_encoder_b_L_N.mif` |
| Node encoder, layer `L`, neuron `N` | `node_encoder_w_L_N.mif` | `node_encoder_b_L_N.mif` |
| MP edge layer, block `B`, layer `L`, neuron `N` | `edge_w_B_L_N.mif` | `edge_b_B_L_N.mif` |
| MP node layer, block `B`, layer `L`, neuron `N` | `node_w_B_L_N.mif` | `node_b_B_L_N.mif` |
| Edge decoder, layer `L`, neuron `N` | `decoder_w_L_N.mif` | `decoder_b_L_N.mif` |
| Output transform, layer `L`, neuron `N` | `output_w_L_N.mif` | `output_b_L_N.mif` |

---

## Simulation

The repository includes testbenches for each major module under `sim_1/new/`. The recommended entry point for a full end-to-end simulation is `tb_top_module.v`.

### Running with Icarus Verilog (iverilog)

1. **Generate `.mif` weight files** from your trained model (not included in the repository).

2. **Compile**:
   ```bash
   iverilog -g2012 -o sim_top \
     sources_1/new/topModule.v \
     sources_1/new/edge_encoder.v \
     sources_1/new/edge_encoder_layer_{1,2,3}.v \
     sources_1/new/node_encoder.v \
     sources_1/new/node_encoder_layer_{1,2,3}.v \
     sources_1/new/storage.v \
     sources_1/new/bram_dual.v \
     sources_1/new/bram_burst_wrapper.v \
     sources_1/new/BRAM_burst_read_data_ss.v \
     sources_1/new/message_passing_wrapper.v \
     sources_1/new/message_passing.v \
     sources_1/new/Edge_Network.v \
     sources_1/new/Node_Network.v \
     sources_1/new/MP_Edge_Layer_B{0..7}_L{1,2,3}.v \
     sources_1/new/MP_Node_Layer_B{0..7}_L{1,2,3}.v \
     sources_1/new/edge_decoder.v \
     sources_1/new/Edge_Decoder_Layer.v \
     sources_1/new/Edge_Output_Layer.v \
     sources_1/new/Edge_Output_Transform.v \
     sources_1/new/neuron.v \
     sources_1/new/multiplier.v \
     sources_1/new/adder.v \
     sources_1/new/ReLu.v \
     sources_1/new/register.v \
     sources_1/new/counter.v \
     sources_1/new/counter_with_enable.v \
     sim_1/new/tb_top_module.v
   ```

3. **Simulate**:
   ```bash
   vvp sim_top
   ```

### Running with Vivado (XSim)

Add all source files under `sources_1/new/*.v` and the testbench `sim_1/new/tb_top_module.v` to a Vivado simulation set. Set `tb_top_module` as the top-level simulation module and run the behavioural simulation.

The pre-synthesised BRAM checkpoint `utils_1/imports/synth_1/bram_init_add1.dcp` can be used with Vivado to initialise block RAM primitives during implementation.

---

## File Structure

```
.
├── sources_1/new/               # RTL source files
│   ├── topModule.v              # Top-level module (FSM + instantiations)
│   ├── edge_encoder.v           # Edge feature encoder (FSM + 3 MLP layers)
│   ├── edge_encoder_layer_{1,2,3}.v
│   ├── node_encoder.v           # Node feature encoder (FSM + 3 MLP layers)
│   ├── node_encoder_layer_{1,2,3}.v
│   ├── storage.v                # Central BRAM storage module
│   ├── bram_dual.v              # Dual-port synchronous BRAM primitive
│   ├── bram_burst_wrapper.v     # Burst-mode BRAM wrapper (write + read)
│   ├── BRAM_burst_read_data_ss.v# Scatter-sum BRAM variant
│   ├── encoder_bram.v           # Standalone encoder output BRAM
│   ├── message_passing_wrapper.v# Sequences 8 MP blocks in series
│   ├── message_passing.v        # Single MP block (Edge + Node networks)
│   ├── Edge_Network.v           # Edge update network
│   ├── Node_Network.v           # Node update network
│   ├── MP_Edge_Layer_B{0-7}_L{1-3}.v  # Edge MLP layers (per block)
│   ├── MP_Node_Layer_B{0-7}_L{1-3}.v  # Node MLP layers (per block)
│   ├── edge_decoder.v           # Edge decoder (FSM + 3 MLP layers)
│   ├── Edge_Decoder_Layer.v     # Decoder MLP layers 1 & 2
│   ├── Edge_Output_Layer.v      # Decoder output layer helper
│   ├── Edge_Output_Transform.v  # Final 32→1 output transform
│   ├── neuron.v                 # Single neuron (MAC + activation)
│   ├── multiplier.v             # Signed multiplier
│   ├── adder.v                  # Signed accumulator
│   ├── ReLu.v                   # ReLU activation + bias
│   ├── register.v               # Element selector from flat array
│   ├── counter.v                # Simple counter
│   ├── counter_with_enable.v    # Counter with enable
│   ├── uram.v                   # URAM wrapper (optional)
│   ├── makelayers.py            # Code-generation script for MLP layers
│   └── mem_files/               # Graph data (.mem files)
│       ├── edge_initial_features.mem
│       ├── node_initial_features.mem
│       ├── connectivity_source_data.mem
│       ├── connectivity_destination_data.mem
│       └── scatter_sum_in.mem
│
├── sim_1/new/                   # Testbenches
│   ├── tb_top_module.v          # End-to-end top-level testbench
│   ├── tb_full_complete.v       # Full pipeline testbench
│   ├── tb_node_edge_network_complete.v
│   ├── tb_edge_network_complete.v
│   ├── tb_message_passing.v
│   ├── tb_neuron.v
│   └── ...
│
├── utils_1/imports/synth_1/
│   └── bram_init_add1.dcp       # Pre-synthesised BRAM checkpoint (Vivado)
│
└── .gitignore                   # Excludes *.mif weight files
```
