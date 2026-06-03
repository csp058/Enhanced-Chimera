% === Time To First Authenticated Channel (TTFAC) Comparison ===
clc; clear; close all;

t = 0:1:200; % from 0 sec to 200 sec

% Standard Chimera (Slow Channel): 180 sec(10 frames) delayed
std_auth = zeros(size(t));
std_auth(t >= 180) = 1;

% Enhanced Chimera (Proposed): 36 sec (2 frames) delayed
enh_auth = zeros(size(t));
enh_auth(t >= 36) = 1;

figure('Name', 'Authentication Latency', 'Color', 'w', 'Position', [150, 150, 600, 450]);
stairs(t, std_auth, '--b', 'LineWidth', 2.5); hold on;
stairs(t, enh_auth, '-r', 'LineWidth', 2.5);

fill([36 180 180 36], [0 0 1 1], 'g', 'FaceAlpha', 0.1, 'EdgeColor', 'none');
text(108, 0.5, '\leftarrow 80% Time Reduction \rightarrow', 'HorizontalAlignment', 'center', 'FontSize', 12, 'FontWeight', 'bold', 'Color', [0 0.5 0]);

grid on;
xlabel('Observation Time (seconds)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Cumulative Probability of Authentication', 'FontSize', 12, 'FontWeight', 'bold');
title('Time To First Authenticated Channel (TTFAC)', 'FontSize', 13, 'FontWeight', 'bold');

ylim([-0.1 1.2]); yticks([0 1]); yticklabels({'0', '1'});

legend('Standard Chimera (Slow Channel)', 'Enhanced Chimera (Proposed)', 'Location', 'east');
set(gca, 'FontSize', 11);

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"onright","rightPanelPercent":23.2}
%---
