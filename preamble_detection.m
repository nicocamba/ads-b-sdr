
%% ADS-B PROJECT - STEP 2: PREAMBLE DETECTION
% Detect Mode S preambles in the recorded IQ signal.
%
% Objectives:
% 1. Load the IQ recording.
% 2. Calculate the received signal power.
% 3. Build the Mode S preamble template.
% 4. Search for the preamble using correlation.
% 5. Identify candidate detections.
% 6. Compare detected signals with the expected preamble structure.

clear;
clc;
close all;

%% 1. Load IQ recording

scriptFolder = fileparts(mfilename('fullpath'));

if isempty(scriptFolder)
    scriptFolder = pwd;
end

inputFile = fullfile(scriptFolder, 'data', 'adsb_capture.mat');

load(inputFile);

fprintf('IQ recording loaded.\n');
fprintf('Sampling frequency: %.3f MS/s\n', Fs/1e6);

%% 2. Select usable samples

% Prefer data_clean if it was saved during acquisition.
% Otherwise, discard frames starting at the first reported overflow.

if exist('data_clean', 'var')

    rxData = data_clean;

elseif exist('overflowFrames', 'var') && any(overflowFrames)

    firstOverflow = find(overflowFrames, 1, 'first');

    lastCleanSample = (firstOverflow-1)*frameSize;

    rxData = data(1:lastCleanSample);

    fprintf('Discarding frames from first reported overflow.\n');

else

    rxData = data;

end

fprintf('Samples used: %d\n', length(rxData));
fprintf('Usable duration: %.6f s\n', length(rxData)/Fs);

%% 3. Calculate received signal power

% Complex IQ signal:
% r[n] = I[n] + jQ[n]
%
% Power envelope:
% p[n] = |r[n]|^2

powerSignal = abs(rxData).^2;

%% 4. Define Mode S preamble

% Preamble duration: 8 microseconds
% Pulse duration: 0.5 microseconds
%
% Pulse starting times:
% 0 us, 1 us, 3.5 us, 4.5 us

preambleDuration = 8e-6;
pulseDuration = 0.5e-6;

pulseStarts = [0, 1e-6, 3.5e-6, 4.5e-6];

Ts = 1/Fs;

%% 5. Generate phase-dependent templates

% The preamble may start between two sampling instants.
% We therefore test several possible fractional sample offsets.

numPhases = 8;

phaseOffsets = (0:numPhases-1)/numPhases * Ts;

templates = cell(numPhases,1);

for q = 1:numPhases

    phase = phaseOffsets(q);

    numTemplateSamples = ceil((preambleDuration + phase)/Ts);

    pulseWeights = zeros(numTemplateSamples,1);
    gapWeights = zeros(numTemplateSamples,1);

    for n = 1:numTemplateSamples

        sampleStart = (n-1)*Ts;
        sampleEnd = n*Ts;

        sampleStart = sampleStart - phase;
        sampleEnd = sampleEnd - phase;

        for m = 1:length(pulseStarts)

            pulseStart = pulseStarts(m);
            pulseEnd = pulseStart + pulseDuration;

            overlapStart = max(sampleStart, pulseStart);
            overlapEnd = min(sampleEnd, pulseEnd);

            overlap = max(0, overlapEnd-overlapStart);

            pulseWeights(n) = pulseWeights(n) + overlap/Ts;

        end

        gapWeights(n) = 1 - pulseWeights(n);

    end

    % Positive weights for expected pulses.
    % Negative weights for expected gaps.

    pulseSum = sum(pulseWeights);
    gapSum = sum(gapWeights);

    template = pulseWeights/pulseSum - gapWeights/gapSum;

    template = template/norm(template);

    templates{q} = template;

end


%% 6. Correlation-based detection

numSamples = length(powerSignal);

correlationScores = -inf(numSamples,1);

% Store the phase hypothesis producing the maximum score
bestPhaseIndex = zeros(numSamples,1);

for q = 1:numPhases

    template = templates{q};

    % Valid correlation
    score = conv(powerSignal, flipud(template), 'valid');

    % Update positions where this phase gives a better score
    betterScore = score > correlationScores(1:length(score));

    correlationScores(betterScore) = score(betterScore);

    bestPhaseIndex(betterScore) = q;

end

% Remove positions without a complete preamble window

validLength = numSamples - max(cellfun(@length, templates)) + 1;

correlationScores = correlationScores(1:validLength);
bestPhaseIndex = bestPhaseIndex(1:validLength);


%% 7. Estimate detection threshold

scoreMedian = median(correlationScores);

scoreMAD = median(abs(correlationScores-scoreMedian));

robustSigma = 1.4826*scoreMAD;

thresholdFactor = 70;  %Tocarlo para detectar más o menos candidatos

detectionThreshold = scoreMedian + thresholdFactor*robustSigma;

fprintf('\nDetection threshold: %.6e\n', detectionThreshold);

%% 8. Find local maxima above threshold

candidateIndices = find( ...
    correlationScores(2:end-1) > correlationScores(1:end-2) & ...
    correlationScores(2:end-1) >= correlationScores(3:end) & ...
    correlationScores(2:end-1) > detectionThreshold) + 1;

% Sort candidates by descending score

[~, order] = sort(correlationScores(candidateIndices), 'descend');

candidateIndices = candidateIndices(order);

% Suppress detections that are very close to one another

minimumSeparation = round(8e-6*Fs);

selectedIndices = [];

for k = 1:length(candidateIndices)

    candidate = candidateIndices(k);

    if isempty(selectedIndices) || ...
            all(abs(candidate-selectedIndices) >= minimumSeparation)

        selectedIndices(end+1,1) = candidate;

    end

end

% Sort detections chronologically

selectedIndices = sort(selectedIndices);


%% 9. Convert detections to time

% Recover the best fractional sampling offset for each candidate

bestPhaseOffsets = phaseOffsets(bestPhaseIndex(selectedIndices)).';

% Estimated physical start time of each preamble

detectionTimes = (selectedIndices-1)/Fs + bestPhaseOffsets;

fprintf('\n========== PREAMBLE DETECTION ==========\n');

fprintf('Number of candidate preambles: %d\n', ...
    length(selectedIndices));

for k = 1:length(selectedIndices)

    fprintf(['Candidate %d: %.6f ms | ' ...
             'Score: %.6e | Phase: %.3f us\n'], ...
        k, ...
        detectionTimes(k)*1e3, ...
        correlationScores(selectedIndices(k)), ...
        bestPhaseOffsets(k)*1e6);

end

fprintf('========================================\n');


%% 10. Plot received power

time = (0:length(powerSignal)-1)/Fs;

figure;

plot(time*1e3, powerSignal);

xlabel('Time (ms)');
ylabel('|r[n]|^2');
title('Received Signal Power');
grid on;

%% 11. Plot correlation score

scoreTime = (0:length(correlationScores)-1)/Fs;

figure;

plot(scoreTime*1e3, correlationScores);
hold on;

yline(detectionThreshold, '--r', 'Detection threshold');

if ~isempty(selectedIndices)

    plot(detectionTimes*1e3, ...
        correlationScores(selectedIndices), ...
        'rv', 'MarkerFaceColor', 'r');

end

xlabel('Time (ms)');
ylabel('Correlation score');
title('Mode S Preamble Detection Metric');

legend('Correlation', 'Threshold', 'Candidates');

grid on;


%% 12. Inspect candidates against expected Mode S preamble

expectedPulseStarts = [0, 1e-6, 3.5e-6, 4.5e-6];

expectedPulseDuration = 0.5e-6;

numCandidatesToInspect = min(length(selectedIndices), 5);

for k = 1:numCandidatesToInspect

    candidateTime = detectionTimes(k);

    % Display 1 us before and 8 us after candidate

    tStart = candidateTime - 1e-6;
    tEnd = candidateTime + 8e-6;

    idxStart = max(1, floor(tStart*Fs)+1);
    idxEnd = min(length(rxData), ceil(tEnd*Fs)+1);

    idx = idxStart:idxEnd;

    % Time relative to candidate, in microseconds

    relativeTime = ((idx-1)/Fs - candidateTime)*1e6;

    % Received power in the selected window

    localPower = powerSignal(idx);

    %% Pulse versus gap energy

pulseMask = false(size(relativeTime));

for m = 1:length(expectedPulseStarts)

    pulseStart = expectedPulseStarts(m)*1e6;
    pulseEnd = pulseStart + expectedPulseDuration*1e6;

    pulseMask = pulseMask | ...
        (relativeTime >= pulseStart & relativeTime < pulseEnd);

end

gapMask = relativeTime >= 0 & ...
          relativeTime < 8 & ...
          ~pulseMask;

E_pulse = mean(localPower(pulseMask));
E_gap = mean(localPower(gapMask));

R = E_pulse / max(E_gap, eps);

fprintf('\nCandidate %d:\n', k);
fprintf('Pulse energy: %.6e\n', E_pulse);
fprintf('Gap energy:   %.6e\n', E_gap);
fprintf('Pulse/Gap ratio: %.3f\n', R);

    % Adaptive vertical scale

    yMax = max(localPower)*1.15;

    % Create figure

    figure;
    hold on;

    % Draw expected pulse intervals

    for m = 1:length(expectedPulseStarts)

        x1 = expectedPulseStarts(m)*1e6;
        x2 = (expectedPulseStarts(m) + expectedPulseDuration)*1e6;

        patch([x1 x2 x2 x1], ...
              [0 0 yMax yMax], ...
              [0.2 0.8 0.3], ...
              'FaceAlpha', 0.20, ...
              'EdgeColor', 'none', ...
              'HandleVisibility', 'off');

        xline(x1, '--g', 'HandleVisibility', 'off');
        xline(x2, '--g', 'HandleVisibility', 'off');

    end

    % Plot received power on top of the shaded intervals

    plot(relativeTime, localPower, '-o', ...
        'Color', [0 0.35 0.8], ...
        'MarkerSize', 5, ...
        'LineWidth', 1.2);

    % Formatting

    xlabel('Time relative to candidate (\mus)');
    ylabel('|r[n]|^2');

    title(sprintf('Candidate %d - Mode S Preamble Inspection', k));

    xlim([-1 8]);
    ylim([0 yMax]);

    grid on;

    legend('Received power', ...
        'Location', 'best');

end



%% 13. Save detection results

outputFile = fullfile(scriptFolder, 'data', ...
    'adsb_preamble_detections.mat');

save(outputFile, ...
    'selectedIndices', ...
    'detectionTimes', ...
    'bestPhaseOffsets', ...
    'bestPhaseIndex', ...
    'correlationScores', ...
    'detectionThreshold', ...
    'Fs', ...
    'fc');

fprintf('\nDetection results saved:\n%s\n', outputFile);



