
%% ADS-B PROJECT - STEP 3: PPM DEMODULATION
%
% Objectives:
% 1. Load the original IQ recording.
% 2. Load the detected preamble positions.
% 3. Extract the 112 us of data following each preamble.
% 4. Calculate the energy in both halves of every bit.
% 5. Recover the 112 bits using PPM.
% 6. Visualize and save the demodulated messages.
%
% ADS-B Mode S Extended Squitter:
% Preamble: 8 us
% Data:     112 bits x 1 us = 112 us
% Total:    120 us

clear;
clc;
close all;

%% 1. Load IQ recording and preamble detections

scriptFolder = fileparts(mfilename('fullpath'));

if isempty(scriptFolder)
    scriptFolder = pwd;
end

dataFolder = fullfile(scriptFolder, 'data');

iqFile = fullfile(dataFolder, 'adsb_capture.mat');
detectionFile = fullfile(dataFolder, ...
    'adsb_preamble_detections.mat');

if ~isfile(iqFile)
    error('IQ recording not found: %s', iqFile);
end

if ~isfile(detectionFile)
    error('Preamble detection file not found: %s', detectionFile);
end

load(iqFile, 'data', 'Fs', 'fc');

load(detectionFile, ...
    'selectedIndices', 'detectionTimes');

rxData = data;

clear data;

fprintf('IQ recording loaded.\n');
fprintf('Preamble detections loaded.\n');
fprintf('Sampling frequency: %.3f MS/s\n', Fs/1e6);
fprintf('Number of candidates: %d\n', ...
    length(detectionTimes));

%% 2. Define ADS-B message parameters

preambleDuration = 8e-6;

bitDuration = 1e-6;
halfBitDuration = 0.5e-6;

numBits = 112;

messageDuration = numBits*bitDuration;

%% 3. Allocate output variables

numCandidates = length(detectionTimes);

% Each row contains one recovered 112-bit message

demodulatedBits = zeros(numCandidates, numBits);

% Store energy measurements for each bit

firstHalfEnergy = zeros(numCandidates, numBits);
secondHalfEnergy = zeros(numCandidates, numBits);

% Store the energy contrast for each bit

bitConfidence = zeros(numCandidates, numBits);

% Store the extracted IQ segments

candidateValid = false(numCandidates,1);

%% 4. Process each candidate

for c = 1:numCandidates

    % Estimated physical beginning of the preamble

    preambleStart = detectionTimes(c);

    % Data begins immediately after the 8 us preamble

    dataStart = preambleStart + preambleDuration;
    dataEnd = dataStart + messageDuration;

    % Check that the complete message is inside the recording

    if dataStart < 0 || dataEnd > length(rxData)/Fs

        fprintf('Candidate %d: insufficient recording samples.\n', c);
        continue;

    end

    candidateValid(c) = true;

    % Process all 112 bits

    for b = 1:numBits

        bitStart = dataStart + (b-1)*bitDuration;

        % First half: 0 to 0.5 us

        t1 = bitStart;
        t2 = bitStart + halfBitDuration;

        % Second half: 0.5 to 1 us

        t3 = bitStart + halfBitDuration;
        t4 = bitStart + bitDuration;

        % Integrate received power over each half-bit.
        % The integration accounts for fractional sample overlaps.

        E1 = integratePower(rxData, Fs, t1, t2);
        E2 = integratePower(rxData, Fs, t3, t4);

        firstHalfEnergy(c,b) = E1;
        secondHalfEnergy(c,b) = E2;

        % PPM decision

        if E1 > E2

            demodulatedBits(c,b) = 1;

        else

            demodulatedBits(c,b) = 0;

        end

        % Normalized energy contrast.
        % Values close to zero indicate uncertain decisions.

        bitConfidence(c,b) = ...
            (E1-E2)/(E1+E2+eps);

    end

    fprintf('Candidate %d/%d demodulated.\n', c, numCandidates);

end

%% 5. Display recovered bit sequences

fprintf('\n========== PPM DEMODULATION ==========\n');

for c = 1:numCandidates

    if ~candidateValid(c)
        continue;
    end

    % Convert bit vector to a character string

    bitString = char(demodulatedBits(c,:) + '0');

    fprintf('\nCandidate %d\n', c);
    fprintf('Preamble time: %.6f ms\n', ...
        detectionTimes(c)*1e3);

    fprintf('Recovered bits:\n');

    % Print in groups of 8 bits for readability

    for k = 1:14

        firstBit = (k-1)*8 + 1;
        lastBit = k*8;

        fprintf('%s ', bitString(firstBit:lastBit));

        if mod(k,4) == 0
            fprintf('\n');
        end

    end

    fprintf('\n');

end

fprintf('\n======================================\n');

%% 6. Plot energy comparison for the first candidates

numCandidatesToPlot = min(3, numCandidates);

for c = 1:numCandidatesToPlot

    if ~candidateValid(c)
        continue;
    end

    figure;

    bitNumbers = 1:numBits;

    plot(bitNumbers, firstHalfEnergy(c,:), '-o', ...
        'LineWidth', 1.1, ...
        'MarkerSize', 3);

    hold on;

    plot(bitNumbers, secondHalfEnergy(c,:), '-o', ...
        'LineWidth', 1.1, ...
        'MarkerSize', 3);

    xlabel('Bit number');
    ylabel('Integrated power');

    title(sprintf('Candidate %d - PPM Half-Bit Energies', c));

    legend('First half', 'Second half');

    xlim([1 numBits]);

    grid on;

end

%% 7. Plot recovered bits

for c = 1:numCandidatesToPlot

    if ~candidateValid(c)
        continue;
    end

    figure;

    stairs(1:numBits, demodulatedBits(c,:), ...
        'LineWidth', 1.3);

    xlabel('Bit number');
    ylabel('Recovered bit');

    title(sprintf('Candidate %d - Recovered ADS-B Bits', c));

    ylim([-0.2 1.2]);
    xlim([1 numBits]);

    yticks([0 1]);

    grid on;

end

%% 8. Plot bit confidence

for c = 1:numCandidatesToPlot

    if ~candidateValid(c)
        continue;
    end

    figure;

    stem(1:numBits, bitConfidence(c,:), ...
        'Marker', 'none');

    xlabel('Bit number');
    ylabel('Normalized energy contrast');

    title(sprintf('Candidate %d - PPM Decision Confidence', c));

    ylim([-1.1 1.1]);
    xlim([1 numBits]);

    grid on;

end

%% 9. Save demodulation results

outputFile = fullfile(dataFolder, ...
    'adsb_demodulated_messages.mat');

save(outputFile, ...
    'demodulatedBits', ...
    'firstHalfEnergy', ...
    'secondHalfEnergy', ...
    'bitConfidence', ...
    'candidateValid', ...
    'detectionTimes', ...
    'Fs', ...
    'fc');

fprintf('\nDemodulation results saved:\n%s\n', outputFile);

%% 10. End

fprintf('\nPPM DEMODULATION COMPLETED.\n');

%% Local function: integrate received power over a time interval

function energy = integratePower(signal, Fs, tStart, tEnd)

    % Each IQ sample represents the interval:
    % [(n-1)/Fs, n/Fs)

    firstSample = max(1, floor(tStart*Fs)+1);
    lastSample = min(length(signal), ceil(tEnd*Fs));

    if firstSample > lastSample
        energy = 0;
        return;
    end

    sampleIndices = (firstSample:lastSample).';

    sampleStartTimes = (sampleIndices-1)/Fs;
    sampleEndTimes = sampleIndices/Fs;

    % Calculate the overlap between each sample interval
    % and the requested integration interval.

    overlapStart = max(sampleStartTimes, tStart);
    overlapEnd = min(sampleEndTimes, tEnd);

    overlapDuration = max(0, overlapEnd-overlapStart);

    % Piecewise-constant power integration

    samplePower = abs(signal(sampleIndices)).^2;

    energy = sum(samplePower .* overlapDuration);

end

