## Plan: AXI-Lite wrapper for top module

Add an AXI4-Lite control/status wrapper so PS can start the accelerator and observe completion/phase. Keep existing datapath untouched; gate FSM start via a new start input.

**Steps**
1. Top-level API change (depends on 2): add `start` input to top_module, gate phase FSM so it stays in IDLE until `start` pulse; optionally add `soft_reset` handling if exposed. Expose `processing_done` and `current_phase` as before.
2. Define register map (parallel with 1): 0x00 CONTROL (bit0 start pulse, bit1 soft_reset opt), 0x04 STATUS (bit0 done, bit1 busy, bits[7:4] phase), 0x08 PHASE full code, 0x0C IRQ_ENABLE (optional), 0x10 IRQ_STATUS (optional latch/clear-on-write). Decide whether busy = not idle/done.
3. AXI-Lite slave wrapper module (depends on 1,2): implement AXI-lite interface (AW/W/B, AR/R channels) with simple single-beat registers. Generate 1-cycle start_pulse when CONTROL.start is written high while not busy; latch/clear soft_reset. Expose STATUS/PHASE from top_module signals; optionally implement IRQ level/pulse on done.
4. Clock/reset alignment (parallel): choose shared clock/reset (AXI aclk tied to accelerator clk; aresetn tied to rstn) or add CDC/synchronizers if clocks differ. Add synchronizer for start_pulse into accel clk domain if clocks differ.
5. Integration wrapper (depends on 3,4): instantiate top_module inside axi_lite wrapper, connect start_pulse to new start input, wire processing_done/current_phase to status regs/IRQ, pass through original clk/rstn. Leave other datapath ports internal.
6. Verification (depends on 5): create/extend testbench to drive AXI-lite writes/reads: write CONTROL.start, wait for STATUS.done, read PHASE sequence; check start ignored when busy; test soft_reset if included; test IRQ if included.

**Relevant files**
- sources_1/new/topModule.v — gate FSM on new start input and optional soft_reset; retain phase/done outputs.
- (new) sources_1/new/axi_lite_top_wrapper.v — AXI4-Lite slave exposing control/status, instantiates top_module.
- sim_1/new/tb_top_module.v (or new TB) — add AXI-lite BFM/simple tasks to exercise control flow.

**Verification**
1. Sim: AXI-lite sequence write CONTROL.start, poll STATUS until done, confirm PHASE transitions in expected order.
2. Sim: write start while busy; ensure ignored or queued per chosen policy.
3. If soft_reset: assert and confirm FSM returns to IDLE and STATUS clears.
4. If IRQ: verify interrupt asserts on done and clears on read/ack.

**Decisions**
- Start policy: ignore new start while busy vs. queue (default: ignore when not IDLE/DONE). Busy definition: phase_state != IDLE and != DONE.
- Clocking: prefer shared aclk/clk; otherwise add 2-flop sync for start pulse and status sampling.
- IRQ: optional; level or pulse on done.

**Further Considerations**
1. Need separate AXI reset (aresetn) or reuse rstn? Recommendation: reuse rstn if same domain; otherwise add small CDC block.
2. Register widths: keep 32-bit registers; pack phase into low bits; leave upper bits reserved for future use.
