
clc; clear; close all;
fprintf('Integrated Acquisition Performance for Gigure 6 and 7 \n'); %[output:4305c6a9]

% 1. Parameter Setting
PRNID = 7;                          
f_chip = 1.023e6;                   % L1C chipping rate (Hz)
T_int = 0.01;                       % Coherent integration time (10ms)
N_chips = f_chip * T_int;           % the number of chips per 10ms interval(10230)
cn0_test_array = 22:1:45;           % Test interval (22 ~ 45 dB-Hz)
num_trials = 10000;                 % Repetition times for Monte Caelo Simulation
P_fa_target = 1e-3;                 % Target pribability of false alarm
duty_factor = 2;                    % Duty Factor (DF=2)
DF_ratio = duty_factor / 33;        % real punctuting ratio (약 6.06%)

% 2. Generation of L1C Pilot code 
[~, L1Cp, L1Co] = gpsL1CCodes(PRNID);
L1Co_sig = 1 - 2*double(L1Co);
L1Cp_sig = 1 - 2*double(L1Cp);
pure_pilot_chips = L1Cp_sig .* L1Co_sig(1);

% 3. Marker Embedding 
slowFast = 0; zcount = 902044820;
hexKey = '2B7E151628AED2A6ABF7158809CF4F3C'; secret_key = hexToBits(hexKey); %[output:3dcc9ab2]
sector_pattern = get_sector_pattern();
symIdx = 0;
[marker_indices, marker_symbols] = marker_overlay_symbol( ...
    PRNID, slowFast, zcount, duty_factor, symIdx, secret_key, sector_pattern);

% 4. Generation of Transmitted Signal for each Scenario
tx_pure = pure_pilot_chips;                         % Pure L1C
tx_std = pure_pilot_chips;                          
tx_std(marker_indices) = marker_symbols;            % Standard Chimera
tx_enh = pure_pilot_chips;
data_bit = -1;
tx_enh(marker_indices) = marker_symbols * data_bit; % Enhanced Chimera

% Initialization of Array storing Result
num_points = length(cn0_test_array);
Pd_sim_pure = zeros(num_points, 1);
Pd_sim_std  = zeros(num_points, 1);
Pd_sim_enh  = zeros(num_points, 1);
Pd_theory_pure = zeros(num_points, 1);
Pd_theory_enh  = zeros(num_points, 1);

local_replica = pure_pilot_chips; 

fprintf('▶ A total of %d Monte Carlo Repetitions \n', num_trials);

% 5. Loop for Simulation and Theoretical Computation
for idx = 1:num_points
    cn0 = cn0_test_array(idx);
    cn0_linear = 10^(cn0/10);
    
    % --- [Theoretical COmputation] ---
    % Pure L1C
    snr_eff_pure = 2 * T_int * cn0_linear;
    V_th_theory = sqrt(-2 * log(P_fa_target));
    Pd_theory_pure(idx) = marcumq(sqrt(2 * snr_eff_pure), V_th_theory);
    
    % Enhanced Chimera
    T_int_enh = T_int * (1 - DF_ratio);
    snr_eff_enh = 2 * T_int_enh * cn0_linear;
    Pd_theory_enh(idx) = marcumq(sqrt(2 * snr_eff_enh), V_th_theory);
    
    % --- [Monte Carlo Simulation] ---
    snr_linear_chip = 10^((cn0 - 10*log10(f_chip)) / 10);
    noise_var = 1 / (2 * snr_linear_chip); 
    noise_sigma = sqrt(noise_var);
    V_th_sim = sqrt(-2 * N_chips * noise_var * log(P_fa_target));
    
    detect_pure = 0; detect_std = 0; detect_enh = 0;
    
    for trial = 1:num_trials
        % AWGN generation
        noise_complex = noise_sigma * randn(N_chips, 1) + 1j * noise_sigma * randn(N_chips, 1);
        
        rx_pure = tx_pure + noise_complex;
        rx_std  = tx_std  + noise_complex;
        rx_enh  = tx_enh  + noise_complex;
        
        Z_pure = abs(sum(rx_pure .* local_replica));
        Z_std  = abs(sum(rx_std  .* local_replica));
        Z_enh  = abs(sum(rx_enh  .* local_replica));
        
        if Z_pure > V_th_sim; detect_pure = detect_pure + 1; end
        if Z_std  > V_th_sim; detect_std  = detect_std  + 1; end
        if Z_enh  > V_th_sim; detect_enh  = detect_enh  + 1; end
    end
    
    Pd_sim_pure(idx) = detect_pure / num_trials;
    Pd_sim_std(idx)  = detect_std  / num_trials;
    Pd_sim_enh(idx)  = detect_enh  / num_trials;
    
    fprintf('C/N0 = %2d dB-Hz | Pure: %.3f | Std: %.3f | Enh: %.3f\n', ...
        cn0, Pd_sim_pure(idx), Pd_sim_std(idx), Pd_sim_enh(idx));
end

%% === Fig. 6: Acquisition Performance (Pd vs C/N0) ===
figure('Name', 'Acquisition Performance (Pd vs C/N0)', 'Color', 'w', 'Position', [100, 150, 700, 550]);

plot(cn0_test_array, Pd_sim_pure, '-k', 'LineWidth', 2.5); hold on;
plot(cn0_test_array, Pd_sim_std, '--b', 'LineWidth', 2, 'Marker', 'o', 'MarkerSize', 6);
plot(cn0_test_array, Pd_sim_enh, ':r', 'LineWidth', 2, 'Marker', 'x', 'MarkerSize', 8);

grid on;
xlim([25 45]); 
ylim([0 1.05]); yticks(0:0.1:1);
xlabel('Received C/N_0 (dB-Hz)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Probability of Detection (P_d)', 'FontSize', 12, 'FontWeight', 'bold');
title(sprintf('Acquisition Performance (P_{fa} = 10^{-3}, T_{int} = 10ms, DF = 2)'), 'FontSize', 13, 'FontWeight', 'bold');
legend('Pure L1C', 'Standard Chimera', 'Enhanced Chimera (Proposed)', 'Location', 'southeast', 'FontSize', 11);
set(gca, 'FontSize', 11);

%% === Fig. 7: Theory vs Simulation ===
figure('Name', 'Theory vs Simulation (Pd vs C/N0)', 'Color', 'w', 'Position', [820, 150, 700, 550]);

plot(cn0_test_array, Pd_theory_pure, '-k', 'LineWidth', 2); hold on;
plot(cn0_test_array, Pd_theory_enh, '-r', 'LineWidth', 2);

plot(cn0_test_array, Pd_sim_pure, 'ks', 'MarkerSize', 8, 'LineWidth', 1.5, 'MarkerFaceColor', 'none');
plot(cn0_test_array, Pd_sim_enh, 'ro', 'MarkerSize', 8, 'LineWidth', 1.5, 'MarkerFaceColor', 'none');

grid on;
xlim([22 36]); 
ylim([0 1.05]); yticks(0:0.1:1);
xlabel('Received C/N_0 (dB-Hz)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Probability of Detection (P_d)', 'FontSize', 12, 'FontWeight', 'bold');
title(sprintf('Implementation Loss: Theory vs. Simulation (P_{fa} = 10^{-3}, T_{int} = 10ms)'), 'FontSize', 13, 'FontWeight', 'bold');
legend('Pure L1C (Theory)', 'Enhanced Chimera (Theory)', ...
       'Pure L1C (Simulation)', 'Enhanced Chimera (Simulation)', ...
       'Location', 'southeast', 'FontSize', 11);
set(gca, 'FontSize', 11);
fprintf('Visualization Completed.\n');








%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"onright","rightPanelPercent":48.2}
%---
%[output:4305c6a9]
%   data: {"dataType":"text","outputData":{"text":"Integrated Acquisition Performance for Gigure 6 and 7 \n","truncated":false}}
%---
%[output:3dcc9ab2]
%   data: {"dataType":"error","outputData":{"errorType":"runtime","text":"hexToBits is not found in the current folder or on the MATLAB path, but exists in:\n    C:\\Simulink_Projects\\(2) Chimera Project\n\n<a href = \"matlab:internal.matlab.desktop.commandwindow.executeCommandForUser('cd ''C:\\Simulink_Projects\\(2) Chimera Project''')\">Change the MATLAB current folder<\/a> or <a href = \"matlab:internal.matlab.desktop.commandwindow.executeCommandForUser('addpath ''C:\\Simulink_Projects\\(2) Chimera Project''')\">add its folder to the MATLAB path<\/a>."}}
%---
