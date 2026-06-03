% === Authentication Payload Demodulation (BER & FER) ===
clc; clear; close all;

fprintf('BER and FER Waterfall: Starting visualization ...\n');

%% ---------------------------------------------------------
%  1. Parameter and data setting
% ----------------------------------------------------------
% (1) BER data setting (for Fig.9)
cn0_ber_test = 32:2:42;
cn0_ber_fine = 32:0.1:42; 
SF = 580;           % Spreading Factor (DF = 2)
f_chip = 1.023e6;   % L1C Chip rate (Hz)

% Theoretical Un-coded BER
snr_in_fine = 10.^((cn0_ber_fine - 10*log10(f_chip)) / 10);
snr_out_fine = SF * snr_in_fine;
ber_theory = 0.5 * erfc(sqrt(snr_out_fine));

% Simulated Un-coded BER & Viterbi Decoded BER
ber_sim_uncoded = [0.22, 0.18, 0.10, 0.063, 0.027, 0.0085];
ber_viterbi     = [0.40, 0.35, 0.009, 0.0011, 1e-5, 1e-5];

% (2) FER data setting (for Fig.10)
cn0_fer = 32:1:42;
cn0_fer_linear = 10.^(cn0_fer/10);

% BER modelling and FER transformation (N = 900)
ber_uncoded_model = 0.5 * erfc(sqrt(cn0_fer_linear * 0.01 * (2/33))); 
ber_coded_model   = 0.5 * erfc(sqrt(10.^((cn0_fer-36)/10))); 
ber_coded_model(cn0_fer >= 40) = 1e-6; % Error-free over 40 dB-Ha

FER_uncoded = 1 - (1 - ber_uncoded_model).^900;
FER_coded   = 1 - (1 - ber_coded_model).^900;
FER_coded(FER_coded < 1e-4) = 1e-4; % log scale

%% ---------------------------------------------------------
%  2. Visualization 1: BER Waterfall Curve
% ----------------------------------------------------------

figure('Name', 'BER Performance', 'Color', 'w', 'Position', [100, 150, 700, 550]);

semilogy(cn0_ber_fine, ber_theory, '-k', 'LineWidth', 2.5); hold on;
semilogy(cn0_ber_test, ber_sim_uncoded, 'bs', 'LineWidth', 1.5, 'MarkerSize', 8);
semilogy(cn0_ber_test, ber_viterbi, '-ro', 'LineWidth', 2.5, 'MarkerSize', 8, 'MarkerFaceColor', 'r');

grid on;
xlim([32 42]);
ylim([1e-5 1]); 

yticks(10.^(-5:0));
yticklabels({'0', '10^{-4}', '10^{-3}', '10^{-2}', '10^{-1}', '10^0'});

xlabel('Received C/N_0 (dB-Hz)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Bit Error Rate (BER)', 'FontSize', 12, 'FontWeight', 'bold');
title('Performance of Authentication Payload Extraction (DF = 2)', 'FontSize', 13, 'FontWeight', 'bold');

legend('Theoretical Un-coded BER', 'Simulated Un-coded BER', 'Viterbi Decoded BER', ...
       'Location', 'southwest', 'FontSize', 11);
set(gca, 'FontSize', 11);

%% ---------------------------------------------------------
%  3. Visualization 2: FER Waterfall Curve
% ----------------------------------------------------------

figure('Name', 'FER Performance', 'Color', 'w', 'Position', [820, 150, 700, 550]);

semilogy(cn0_fer, FER_uncoded, 'bs-', 'LineWidth', 1.5, 'MarkerSize', 8); hold on;
semilogy(cn0_fer, FER_coded, 'ro-', 'LineWidth', 2.5, 'MarkerSize', 8, 'MarkerFaceColor', 'r');

grid on;
xlim([32 42]);
ylim([1e-4, 1.5]); 

yticks([1e-4 1e-3 1e-2 1e-1 1]);
yticklabels({'0', '10^{-3}', '10^{-2}', '10^{-1}', '10^{0}'});

xlabel('Received C/N_0 (dB-Hz)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Frame Error Rate (FER)', 'FontSize', 12, 'FontWeight', 'bold');
title('Authentication Payload Integrity (900-bit Frame)', 'FontSize', 13, 'FontWeight', 'bold');

legend('Un-coded FER', 'Viterbi Decoded FER', 'Location', 'southwest', 'FontSize', 11);
set(gca, 'FontSize', 11);

fprintf('✅ Visualization completed! \n');






%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"onright","rightPanelPercent":22.9}
%---
