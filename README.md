# Enhanced Chimera (DLCV) GPS L1C Baseband Simulator

## Overview
This repository contains a comprehensive, MATLAB-based end-to-end baseband simulator for the Enhanced Chimera protocol. It strictly evaluates the physical-layer robustness and cryptographic integrity of the GPS L1C (CNAV-2) signal utilizing Deterministic Location, Cryptographic Value (DLCV) puncturing.

Unlike conventional implementations, this simulator uniquely integrates rigorous cryptographic authentication directly into the physical layer signal processing chain. The simulation demonstrates that a 900-bit cryptographic payload can be seamlessly embedded, transmitted over a noisy channel, naturally tracked by a Phase-Locked Loop (PLL), and authenticated via ECDSA-512 and TESLA hash chains without compromising the backward compatibility of the Standard Chimera protocol.

## Key Features
- Signal Generation: GPS L1C (CNAV-2) data (L1Cd) and pilot (L1Cp) components with deterministic puncturing (First 580 non-TMBOC chips).
- Realistic Channel Modeling: Includes AWGN (40 dB-Hz C/N0), code delay, and a residual Doppler error (5 Hz) to simulate post-FLL handover scenarios.
- Signal Tracking: Employs a realistic Phase-Locked Loop (PLL) with a 200-symbol transient warm-  up period.
- FEC Demodulation:** Full recovery of CNAV-2 subframes via BCH (Subframe 1) and LDPC (Subframes 2 & 3) decoding.
- End-to-End Cryptography: Generates and verifies an ECDSA-512 (secp256r1) Root Signature, a TESLA Hash Chain (n=10), and a Message Authentication Code (MAC) bound to the raw, unencoded navigation subframes.

## Experimental Environment (Prerequisites)
To run this simulator successfully, the following software environment is required:
- Platform: MATLAB (R2021a or later is highly recommended for optimal Java Cryptography Architecture integration and string handling).
- Required Toolboxes:
- Communications Toolbox** (Required for LDPC encoding/decoding, BCH processing, Viterbi decoding, CRC generation/detection, and interleaving).
- Satellite Communications Toolbox** (Required for core GPS spreading code generation, e.g., ` gpsL1CCodes`).

## Repository Structure
Ensure all the following files are located in the same working directory before execution:
- `Main_Enhanced_Chimera.m` : The main execution script containing the end-to-end simulation pipeline.
- `MATLAB Output (Main_Enhanced_Chimera).pdf` : Output result of executing 'Main_Enhanced_Chimera.m' script.
- `gpsNavigationConfig.m` : A lightweight, custom configuration class optimized specifically for CNAV-2 (L1C) parameters.
- `gpsNAVDataEncode.m` : A custom encoder modified to output both the fully encoded 1800-bit frame and 
the pure, raw navigation subframes (SF1, SF2, SF3) for backward-compatible MAC generation.
- `L1CLDPCParityCheckMatrices.mat` : A mandatory data file containing the sparse parity-check matrices (A1, B1, C1, E1, T1, etc.) defined in IS-GPS-800j for LDPC error correction.
- `simulation_code_Fig(7-10).m`: scripts for drawing several figures in the manuscript.

## Usage & Precautions
1. Execution Time: The simulation processes the signal chip-by-chip and symbol-by-symbol through a closed-loop PLL, followed by intensive LDPC and Viterbi decoding. Depending on your CPU specifications, the execution may take a few moments.
2. Warm-up Period: The simulator inherently includes a `200-symbol` warm-up period (`num_symbols_warmup`) to allow the PLL to achieve steady-state phase lock naturally. **Do not arbitrarily change this value** unless you also mathematically realign the payload overlay indices; otherwise, the Viterbi decoder will suffer from frame misalignment.
3. Cryptographic Operations: All cryptographic hash (SHA-256) and digital signature (ECDSA) operations are implemented using MATLAB's built-in Java bindings (`java.security.*`). **No external cryptographic libraries or third-party installations are required.**
4. .mat File Integrity: Do not open and manually edit the `L1CLDPCParityCheckMatrices.mat` file using the MATLAB Variable Editor. Altering the sparse matrix definitions will cause the FEC decoding phase to fail entirely.
5. Output Results: Upon successful execution, the script will output the decoded navigation parameters (Ephemeris data) to the console, followed by a step-by-step cryptographic verification report. It will also generate three figures demonstrating the Acquisition 3D Correlation Map, 
  I/Q Correlator History, and the post-lock BPSK Constellation.

