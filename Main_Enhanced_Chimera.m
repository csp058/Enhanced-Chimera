% =========================================================================
% ENHANCED CHIMERA (DLCV) GPS L1C BASEBAND SIMULATOR
% =========================================================================
% Description:
%   This script provides a comprehensive end-to-end baseband simulation of 
%   the Enhanced Chimera protocol, utilizing Deterministic Location, 
%   Cryptographic Value (DLCV) puncturing on the GPS L1C (CNAV-2) signal.
%   It strictly evaluates the physical-layer robustness and cryptographic 
%   integrity of the receiver under realistic channel conditions.
%
% Key Features & Pipeline:
%   1. Cryptographic Initialization: 
%      - Generates an ECDSA-512 (secp256r1) key pair and signs the root key.
%      - Constructs a TESLA hash chain and binds the MAC to the navigation data.
%   2. Signal Generation & Puncturing (Tx):
%      - Generates GPS L1C data (L1Cd) and pilot (L1Cp) components.
%      - Embeds a 900-bit "authentication payload" into the pilot channel using 
%        deterministic puncturing (First 580 non-TMBOC chips per symbol).
%   3. Realistic Channel Modeling:
%      - Applies AWGN (40 dB-Hz C/N0) and a residual Doppler error (5 Hz) 
%        to simulate a post-FLL handover scenario.
%   4. Signal Tracking (Rx):
%      - Implements a realistic Phase-Locked Loop (PLL) with a 200-symbol 
%        warm-up period to naturally pull-in the residual frequency error.
%      - Utilizes an ideal Delay-Locked Loop (DLL) to isolate PLL performance 
%        and prevent random walk over extended simulation times.
%   5. Data & Payload Demodulation:
%      - Recovers CNAV-2 subframes via BCH and LDPC (Standard Chimera compliant).
%      - Extracts the punctured physical payload via Viterbi decoding.
%   6. End-to-End Authentication:
%      - Verifies the physical payload CRC.
%      - Validates the ECDSA-512 Root Signature.
%      - Verifies the TESLA Epoch Key via hash chain.
%      - Authenticates the recovered raw navigation subframes using the MAC.
%
% Author : Chang-Seop Park, Dankook Univ.
% Date   : June 10, 2026.

%% --------------------------------------------------------
%% Part 1: Signal Generation & Cryptographic Initialization
%% --------------------------------------------------------
clc; clear; close all;
fprintf('[Part 1] Signal Generation & Cryptographic Initialization \n');

%% ECDSA Key-Pair Generation
fprintf('[Init] Generating ECDSA (secp256r1) Key Pair...\n');
keyGen = java.security.KeyPairGenerator.getInstance('EC');
ecSpec = java.security.spec.ECGenParameterSpec('secp256r1');
keyGen.initialize(ecSpec, java.security.SecureRandom());
keyPair = keyGen.generateKeyPair();
privateKey = keyPair.getPrivate();
publicKey = keyPair.getPublic();

PRNID = 7;                              % Satellite ID                        
f_chip = 1.023e6; 	                    % Chipping rate 
% Set the sampling frequency to 24 times the chipping rate and 
% calculate the number of samples per chip.
fs = f_chip * 24;                       
samples_per_chip = fs / f_chip;

%% --- Generation of Data Code, Pilot Code, and Overlay Code
[L1Cd, L1Cp, L1Co] = gpsL1CCodes(PRNID);

num_symbols_warmup  = 200;   
num_symbols_payload = 1800;  
num_symbols_buffer  = 10; 
total_symbols       = num_symbols_warmup + num_symbols_payload + num_symbols_buffer; 

%% Extend and combine the pilot channel (L1Cp and L1Co) codes 
%% to match the total simulation symbol length.
L1Co_extended = repmat(L1Co, 2, 1); 
L1Co_extended = L1Co_extended(1:total_symbols); 
L1Co_expanded = repelem(L1Co_extended, 10230, 1);  
L1Cp_expanded = repmat(L1Cp, total_symbols, 1);    
L1Co_sig = 1 - 2*double(L1Co_expanded);   
L1Cp_sig = 1 - 2*double(L1Cp_expanded);	               	    
combined_Psig = L1Cp_sig .* L1Co_sig; 	                                                                                   

%% Extract fixed indices of the first 580 non-TMBOC chips (DLCV) 
%% for deterministic payload insertion.
SF = 580; 
is_tmboc_chip = false(10230, 1);
for i = 0:33:10230-33, is_tmboc_chip(i + [1, 5, 7, 30]) = true; end
non_tmboc_idx = find(~is_tmboc_chip);
fixed_marker_indices = non_tmboc_idx(1:SF); 

%% --- CNAV-2 Data Generation ---
cfgCNAV2 = gpsNavigationConfig('SignalType', 'CNAV2', 'PRNID', PRNID);   
[dataCNAV2_full, rawSF1_full, rawSF2_full, rawSF3_full] = gpsNAVDataEncode(cfgCNAV2);
dataCNAV2 = dataCNAV2_full(1:num_symbols_payload);
tx_raw_subframes = [rawSF1_full(:, 1); rawSF2_full(:, 1); rawSF3_full(:, 1)];

%% --- Cryptographic Payload Generation with TESLA hash chain and ECDSA Signature
fprintf('[Tx] Generating TESLA Hash Chain (n=10)...\n');

% TESLA hash chain generation (from K_10 to K_0)
n_chain = 10;
K_chain = cell(n_chain + 1, 1);
K_chain{11} = randi([0 1], 192, 1); % K_10 (Random Seed)

for i = 10:-1:1
    % K_{i-1} = Hash(K_i)
    K_chain{i} = compute_proxy_hash(K_chain{i+1}, 192); 
end

root_key = K_chain{1};              % K_0 (Root Epoch Key)
stored_prev_epoch_key = K_chain{4}; % K_3 (Previous Epoch Key)
current_epoch_key = K_chain{5};     % K_4 (Current Epoch Key)
cMeta = randi([0 1], 44, 1);

% ECDSA signature generation for Root Epoch Key (K_0)
ecdsaSign = java.security.Signature.getInstance('SHA256withECDSA');
ecdsaSign.initSign(privateKey);

k0_str = char(root_key' + '0');
k0_bytes = typecast(uint8(bin2dec(reshape(k0_str, 8, 24)')), 'int8');

ecdsaSign.update(k0_bytes); % Signing K_0
derSignature = ecdsaSign.sign();
root_signature = extract_512bit_signature(derSignature);

%% --- Payload Assembly, Convolutional Encoding, and BPSK-mapping with Spreading
enhanced_payload_bits = generate_chimera_crypto_payload(root_signature, current_epoch_key, cMeta, tx_raw_subframes);
trellis_enhanced = poly2trellis(7, [171 133]);
enhanced_coded_bpsk = 1 - 2 * double(convenc(enhanced_payload_bits, trellis_enhanced)); 

for symIdx = 0:(num_symbols_payload - 1)
    actual_symIdx = num_symbols_warmup + symIdx; 
    enhanced_marker_symbols = repmat(enhanced_coded_bpsk(symIdx + 1), SF, 1);
    absolute_indices = (actual_symIdx * 10230) + fixed_marker_indices;
    combined_Psig(absolute_indices) = enhanced_marker_symbols;
end
fprintf('[Tx] Deterministic puncturing and Payload Insertion.\n');

%% Upsample the pilot signal and combine it with the data channel (L1Cd) 
%% padded with warm-up and buffer segments.
Psig_upsampled = repelem(combined_Psig(:), samples_per_chip, 1);
L1Cf = [ones(num_symbols_warmup, 1); dataCNAV2; ones(num_symbols_buffer, 1)]; 
L1Cf_expanded = repelem(L1Cf, 10230, 1);
L1Cd_full = repmat(L1Cd, total_symbols, 1);  
combined_Dsig = (1 - 2*double(L1Cf_expanded)) .* (1 - 2*double(L1Cd_full));
L1Cd_upsampled = repelem(combined_Dsig, samples_per_chip, 1);

%% Identify indices for TMBOC (BOC(6,1)) chips on the pilot channel 
%% as specified by the IS-GPS-800 standard.
boc61_idx = false(length(combined_Psig), 1);
for i = 0:33:length(combined_Psig)-33, boc61_idx(i + [1, 5, 7, 30]) = true; end
is_boc61 = repelem(boc61_idx, samples_per_chip, 1);
t = (0:length(Psig_upsampled)-1)' / fs;
sub_boc11 = sign(sin(2 * pi * 1.023e6 * t));
sub_boc61 = sign(sin(2 * pi * 6.138e6 * t));

%% Modulate the pilot and data channels with BOC(1,1) and BOC(6,1) 
%% subcarriers and combine them into the final baseband signal.
L1Cp_wave = zeros(length(Psig_upsampled), 1);
L1Cp_wave(is_boc61) = Psig_upsampled(is_boc61) .* sub_boc61(is_boc61);
L1Cp_wave(~is_boc61) = Psig_upsampled(~is_boc61) .* sub_boc11(~is_boc61);
L1Cd_wave = L1Cd_upsampled .* sub_boc11;
L1C_total = (0.5 * L1Cd_wave) + ((sqrt(3)/2) * L1Cp_wave);

%% Upconvert to Intermediate Frequency (IF) and apply a realistic 5 Hz 
%% Doppler residual, code delay, and AWGN.
f_if = 4e6; doppler_true = 2505; code_delay_true = 500;     
L1C_tx = L1C_total .* cos(2 * pi * (f_if + doppler_true) * t);
L1C_rx = awgn(circshift(L1C_tx, code_delay_true), 40 - 10*log10(fs), 'measured');

%% --------------------------------------------------------
%% Part 2: Coarse Signal Acquisition
%% --------------------------------------------------------
fprintf('[Part 2] Coarse Signal Acquisition \n');

num_samples_acq = fs * 0.01;
acq_map = zeros(21, num_samples_acq);
doppler_search = -5000:500:5000;
local_code = L1Cp_wave(1:num_samples_acq);

% Perform FFT-based coarse signal acquisition across the Doppler 
% search range to estimate initial frequency and code phase.
for i = 1:length(doppler_search)
    carrier_i = exp(-1j * 2 * pi * (f_if + doppler_search(i)) * ((0:num_samples_acq-1)'/fs));
    acq_map(i, :) = abs(ifft(fft(L1C_rx(1:num_samples_acq) .* carrier_i) .* conj(fft(local_code)))).^2;
end
[~, max_idx] = max(acq_map(:));
[f_idx, t_idx] = ind2sub(size(acq_map), max_idx);

%% [Graph Output] Acquisition 3D Correlation Map
figure('Name', 'Acquisition 3D Correlation Map', 'Color', 'w');
[X_Doppler, Y_Code] = meshgrid(doppler_search, 1:num_samples_acq);
surf(X_Doppler, Y_Code, acq_map', 'EdgeColor', 'none');
title('Coarse Acquisition: Cross-Ambiguity Function');
xlabel('Doppler Shift (Hz)');
ylabel('Code Phase (Samples)');
zlabel('Correlation Magnitude');
view(-40, 30);
colormap('jet');
colorbar;

%% --------------------------------------------------------
%% Part 3: Signal Tracking (Realistic PLL + Ideal DLL)
%% --------------------------------------------------------
fprintf('[Part 3] Signal Tracking (Realistic PLL + Ideal DLL) \n');

dump_size = num_samples_acq;    
zeta = 0.707; PLL_BW = 10;
C1_pll = 2 * zeta * (PLL_BW * 8/3) / (2*pi); 
C2_pll = ((PLL_BW * 8/3)^2 * 0.01) / (2*pi);
curr_doppler = doppler_search(f_idx); 
rem_doppler_phase = 0; pll_I = 0; 

accu_prompt = zeros(total_symbols, 1);
track_history = zeros(total_symbols, 1);
saved_rx_chips_complex = zeros(total_symbols, 10230);

L1Cd_wave_pure = repelem((1 - 2*double(L1Cd_full)), samples_per_chip, 1) .* sub_boc11;
L1Cp_wave_pure = zeros(length(Psig_upsampled), 1);
Psig_pure = repelem(L1Cp_sig .* L1Co_sig, samples_per_chip, 1);
L1Cp_wave_pure(is_boc61) = Psig_pure(is_boc61) .* sub_boc61(is_boc61);
L1Cp_wave_pure(~is_boc61) = Psig_pure(~is_boc61) .* sub_boc11(~is_boc61);

% Execute a realistic PLL tracking loop utilizing an ideal DLL to isolate 
% phase pull-in and track the residual Doppler error.
for step = 1:total_symbols
    start_s = t_idx + (step-1)*dump_size; 
    if start_s < 1 || start_s + dump_size - 1 > length(L1C_rx), break; end  
    phase_doppler = rem_doppler_phase + 2*pi*curr_doppler * ((0:dump_size-1)'/fs);
    rem_doppler_phase = mod(rem_doppler_phase + 2*pi*curr_doppler * 0.01, 2*pi);
    
    wipeoff = @(off) L1C_rx(start_s + off : start_s + off + dump_size - 1) .* ...
        exp(-1j * (2*pi*f_if * ((start_s + off - 1 : start_s + off + dump_size - 2)'/fs) + phase_doppler));
    
    sig_p = wipeoff(0); 
    saved_rx_chips_complex(step, :) = sum(reshape(sig_p .* sub_boc11(1:dump_size), samples_per_chip, []), 1).';
    local_p = L1Cp_wave_pure((step-1)*dump_size + 1 : step*dump_size);
    I_P = real(sum(sig_p .* local_p)); Q_P = imag(sum(sig_p .* local_p));

    phi_err = atan2(Q_P, I_P); 
    pll_I = pll_I + (C2_pll * phi_err); 
    curr_doppler = doppler_search(f_idx) + C1_pll * phi_err + pll_I;
    
    accu_prompt(step) = sum(sig_p .* L1Cd_wave_pure((step-1)*dump_size + 1 : step*dump_size));   
    track_history(step) = curr_doppler; 
end
normalized_data = accu_prompt .* exp(-1j * angle(mean(accu_prompt(num_symbols_warmup+50:end))));

%% [Graph Output] Signal Tracking Performance (I/Q & Constellation)
figure('Name', 'Tracking Performance', 'Color', 'w', 'Position', [100, 100, 1000, 400]);

% I/Q History Plot
subplot(1, 2, 1);
plot(1:total_symbols, real(normalized_data), 'b', 'DisplayName', 'In-Phase (I)'); hold on;
plot(1:total_symbols, imag(normalized_data), 'r', 'DisplayName', 'Quadrature (Q)');
xline(num_symbols_warmup, 'k--', 'Warm-up End (Lock)', 'LineWidth', 2);
grid on;
title('I/Q Correlator Outputs Over Time');
xlabel('Symbol Index'); ylabel('Amplitude');
legend('Location', 'best');

% Constellation Plot
subplot(1, 2, 2);
payload_complex = normalized_data(num_symbols_warmup+1 : end);
scatter(real(payload_complex), imag(payload_complex), 15, 'b', 'filled', 'MarkerFaceAlpha', 0.5);
grid on; hold on;
xline(0, 'k-', 'LineWidth', 1.5); yline(0, 'k-', 'LineWidth', 1.5);
title('BPSK Constellation (Post Warm-up)');
xlabel('In-Phase (I)'); ylabel('Quadrature (Q)');
axis square;
max_amp = max(abs(real(payload_complex))) * 1.5;
xlim([-max_amp, max_amp]); ylim([-max_amp, max_amp]);

%% --------------------------------------------------------
%% Part 4: CNAV-2 Data Channel Decoding (BCH & LDPC)
%% --------------------------------------------------------
fprintf('[Part 4] CNAV-2 Data Channel Decoding (BCH & LDPC) \n');

demod_bits = normalized_data(num_symbols_warmup+1 : num_symbols_warmup+num_symbols_payload) < 0;
errCnt = zeros(512, 1);

% Brute-force recover the Subframe 1 (BCH) Time of Interval 
% (TOI) value by testing all 512 possible bit patterns.
for i = 0:511, errCnt(i+1) = sum(xor(double(demod_bits(1:52)).', custom_gpsTOIEnc(int2bit(i, 9)).')); end
[~, bestIdx] = min(errCnt); 
recoveredToi = bestIdx - 1;
fprintf('[Rx] Subframe 1 TOI (BCH) Recovered: %d\n', recoveredToi);

% Deinterleave Subframes 2 and 3 and perform LDPC error correction 
% decoding using the pre-loaded parity-check matrices.
try
    deintrlvd = matdeintrlv([demod_bits(53:1252); demod_bits(1253:1800)], 38, 46);
    load("L1CLDPCParityCheckMatrices.mat", "A1","B1","C1","E1","T1", "A2","B2","C2","E2","T2");
    
    H2 = [logical(sparse(A1(:,1),A1(:,2),1,599,600)), logical(sparse(B1(:,1),B1(:,2),1,599,1)), logical(sparse(T1(:,1),T1(:,2),1,599,599)); ...
          logical(sparse(C1(:,1),C1(:,2),1,1,600)), true, logical(sparse(E1(:,1),E1(:,2),1,1,599))];
    H3 = [logical(sparse(A2(:,1),A2(:,2),1,273,274)), logical(sparse(B2(:,1),B2(:,2),1,273,1)), logical(sparse(T2(:,1),T2(:,2),1,273,273)); ...
          logical(sparse(C2(:,1),C2(:,2),1,1,274)), true, logical(sparse(E2(:,1),E2(:,2),1,1,273))];

    sf2LLR = (1 - 2 * double(deintrlvd(1:1200))) * 10; sf3LLR = (1 - 2 * double(deintrlvd(1201:1748))) * 10;
    decodedSF2 = ldpcDecode(sf2LLR, ldpcDecoderConfig(H2), 30); 
    decodedSF3 = ldpcDecode(sf3LLR, ldpcDecoderConfig(H3), 30);

    crcDetector = comm.CRCDetector('Polynomial', 'z^24 + z^23 + z^18 + z^17 + z^14 + z^11 + z^10 + z^7 + z^6 + z^5 + z^4 + z^3 + z + 1');
    [~, err2] = crcDetector(double(decodedSF2)); [~, err3] = crcDetector(double(decodedSF3));

    if err2 == 0, fprintf('[Rx] Subframe 2 (LDPC): CRC Passed!\n'); else, fprintf('[!] Subframe 2: CRC Failed\n'); end
    if err3 == 0, fprintf('[Rx] Subframe 3 (LDPC): CRC Passed!\n'); else, fprintf('[!] Subframe 3: CRC Failed\n'); end
    
    if err2 == 0 && err3 == 0
        rec_clean_sf1 = custom_gpsTOIEnc(int2bit(recoveredToi, 9));
        rec_raw_subframes = [rec_clean_sf1(:); double(decodedSF2(:)); double(decodedSF3(:))];
        fprintf('[Rx] Receiver successfully reconstructed the pure raw subframes (926 bits).\n');
    else
        error('FEC Failed. Cannot reconstruct raw subframes safely.');
    end
catch
    fprintf('[Rx] Parity check matrices not found or decoding error.\n');
end

%% --------------------------------------------------------
%% Part 5: Physical Payload Extraction & Viterbi Decoding
%% --------------------------------------------------------
fprintf('[Part 5] Physical Payload Extraction & Viterbi Decoding \n');

soft_decision_values = zeros(num_symbols_payload, 1); 
is_mk = false(10230, 1); is_mk(fixed_marker_indices) = true;

% Extract soft-decision values from the fixed DLCV marker indices 
% within the phase-synchronized pilot symbols.
for step = 1:num_symbols_payload
    actual_step = num_symbols_warmup + step; 
    c_complex = saved_rx_chips_complex(actual_step, :)';
    idx_s = (actual_step - 1) * 10230 + 1; 
    l_pilot = L1Cp_sig(idx_s : actual_step * 10230) .* L1Co_sig(idx_s : actual_step * 10230);
    c_real = real(c_complex .* exp(-1j * angle(sum(c_complex(~is_mk) .* l_pilot(~is_mk)))));
    soft_decision_values(step) = sum(c_real(fixed_marker_indices));
end

recovered_payload = vitdec(soft_decision_values, trellis_enhanced, 35, 'trunc', 'unquant');
num_errs = sum(recovered_payload ~= enhanced_payload_bits);
fprintf('[Rx] Viterbi Decoding Errors: %d / 900\n', num_errs);

%% --------------------------------------------------------
%% Part 6: Cryptographic Verification (Receiver Side)
%% --------------------------------------------------------
fprintf('[Part 6] Cryptographic Verification (Receiver Side) \n');

verify_chimera_crypto_payload(recovered_payload, stored_prev_epoch_key, rec_raw_subframes, publicKey);

%% --------------------------------------------------------
%% Local Helper Functions for Cryptographic Operations
%% --------------------------------------------------------

function payload_bits = generate_chimera_crypto_payload(root_sig, current_key, cmeta, raw_subframes)
    mac_input = [raw_subframes; cmeta; current_key];
    mac = compute_proxy_hash(mac_input, 128); 
    payload_body = [root_sig; current_key; mac; cmeta];
    crc_gen = comm.CRCGenerator('Polynomial', 'z^24 + z^23 + z^18 + z^17 + z^14 + z^11 + z^10 + z^7 + z^6 + z^5 + z^4 + z^3 + z + 1');
    payload_bits = crc_gen(payload_body);
end

function verify_chimera_crypto_payload(payload_bits, stored_prev_key, rec_raw_subframes, publicKey)
    % Verification of Pilot CRC
    crc_det = comm.CRCDetector('Polynomial', 'z^24 + z^23 + z^18 + z^17 + z^14 + z^11 + z^10 + z^7 + z^6 + z^5 + z^4 + z^3 + z + 1');
    [payload_body, crc_err] = crc_det(payload_bits);
    is_crc_valid = (crc_err == 0);
    
    if ~is_crc_valid
        fprintf('[!] Authentication Failed: CRC Error in physical payload.\n');
        return;
    end
    fprintf('[Rx] Pilot CRC Check        : PASS\n');

    % Payload Parsing
    rec_root_sig  = payload_body(1:512);
    rec_epoch_key = payload_body(513:704); % 수신된 K_4
    rec_mac       = payload_body(705:832);
    rec_cmeta     = payload_body(833:876);

    % Verification of TESLA Key Chain (Hash(K_4) == K_3 검증)
    computed_prev_key = compute_proxy_hash(rec_epoch_key, 192);
    is_key_valid = isequal(computed_prev_key, stored_prev_key);
    
    if is_key_valid
        fprintf('[Rx] TESLA Key Chain Verify : PASS (Hash matched stored commitment K_3)\n');
    else
        fprintf('[!] TESLA Key Chain Verify : FAIL (Spoofing detected)\n');
    end

    % Verification of (ECDSA) Signed Root Key
    % Recovery of Root Key (K_0) from received Epoch Key (K_4)
    derived_k = rec_epoch_key;
    for i = 1:4
        derived_k = compute_proxy_hash(derived_k, 192);
    end
    derived_k0 = derived_k; % Recovered K_0

    reconstructed_der = repack_to_der(rec_root_sig);
    ecdsaVerify = java.security.Signature.getInstance('SHA256withECDSA');
    ecdsaVerify.initVerify(publicKey);
    
    k0_str = char(derived_k0' + '0');
    k0_bytes = typecast(uint8(bin2dec(reshape(k0_str, 8, 24)')), 'int8');
    
    ecdsaVerify.update(k0_bytes);
    is_sig_valid = ecdsaVerify.verify(reconstructed_der);

    if is_sig_valid
        fprintf('[Rx] Root Signature Verify  : PASS (ECDSA-512 Validates Derived K_0)\n');
    else
        fprintf('[!] Root Signature Verify  : FAIL (Invalid Digital Signature for Root Key)\n');
    end

    % 3) MAC verification of navigation Message.
    mac_input = [rec_raw_subframes; rec_cmeta; rec_epoch_key];
    computed_mac = compute_proxy_hash(mac_input, 128);
    is_mac_valid = isequal(computed_mac, rec_mac);

    if is_mac_valid
        fprintf('[Rx] Navigation MAC Verify  : PASS (Navigation Subframes are Authentic & Intact)\n');
    else
        fprintf('[!] Navigation MAC Verify  : FAIL (Navigation Data Manipulation Detected!)\n');
    end

    if is_crc_valid && is_key_valid && is_mac_valid && is_sig_valid
        fprintf('\n[+++] Cryptographic Authentication Fully Successful! Signal is Genuine. [+++]\n');
    end
end

function hash_bits = compute_proxy_hash(input_bits, output_length)
    pad_len = 8 - mod(length(input_bits), 8);
    if pad_len ~= 8, input_bits = [input_bits; zeros(pad_len, 1)]; end
    
    num_bytes = length(input_bits) / 8;
    input_bytes = zeros(num_bytes, 1, 'uint8');
    for i = 1:num_bytes
        byte_bits = input_bits((i-1)*8 + 1 : i*8);
        input_bytes(i) = uint8(bin2dec(char(byte_bits' + '0')));
    end

    md = java.security.MessageDigest.getInstance('SHA-256');
    hash_bytes = typecast(md.digest(int8(input_bytes)), 'uint8');

    hash_bits_str = dec2bin(hash_bytes, 8)';
    hash_bits_all = hash_bits_str(:) - '0';
    hash_bits = hash_bits_all(1:output_length);
end

function y = custom_gpsTOIEnc(x)
    msg = x(:).';
    pns = comm.PNSequence('Polynomial',[1 1 0 0 1 1 1 1 1], ...
        'InitialConditions', fliplr(msg(2:end)),'SamplesPerFrame',51);
    y = [msg(1); xor(msg(1),pns())];
end

% --- ECDSA-512 Helper Functions ---
function sigBits = extract_512bit_signature(derBytes)
    der = typecast(derBytes, 'uint8');
    idx = 3; 
    idx = idx + 1; 
    rLen = double(der(idx)); idx = idx + 1;
    r = der(idx : idx+rLen-1); idx = idx + rLen;
    idx = idx + 1; 
    sLen = double(der(idx)); idx = idx + 1;
    s = der(idx : idx+sLen-1);
    
    r = trim_or_pad(r, 32);
    s = trim_or_pad(s, 32);
    raw64 = [r(:); s(:)];
    bits_str = dec2bin(raw64, 8)';
    sigBits = (bits_str(:) - '0');
end

function out = trim_or_pad(val, targetLen)
    if length(val) > targetLen
        out = val(end-targetLen+1:end);
    else
        out = [zeros(targetLen-length(val), 1, 'uint8'); val(:)];
    end
end

function derBytes = repack_to_der(sigBits)

    sig_str = char(sigBits' + '0');
    raw64 = uint8(bin2dec(reshape(sig_str, 8, 64)'));   

    r_raw = raw64(1:32);
    s_raw = raw64(33:64);    
    r = format_der_integer(r_raw);
    s = format_der_integer(s_raw);
    rLen = length(r);
    sLen = length(s);
    totalLen = 4 + rLen + sLen;
   
    der = [uint8(48); uint8(totalLen); ...
           uint8(2); uint8(rLen); r(:); ...
           uint8(2); uint8(sLen); s(:)];
           
    derBytes = typecast(der, 'int8');
end

function out = format_der_integer(val)
    idx = 1;
    while idx < length(val) && val(idx) == 0
        idx = idx + 1;
    end
    val = val(idx:end);
    if bitand(val(1), 128)
        out = [uint8(0); val(:)];
    else
        out = val(:);
    end
end

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"onright","rightPanelPercent":23.3}
%---
