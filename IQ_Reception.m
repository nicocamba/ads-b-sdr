
%% ADS-B PROJECT - STEP 1: IQ ACQUISITION AND INSPECTION
% ADALM-PLUTO connected through USB
%
% Objectives:
% 1. Configure Pluto at 1090 MHz.
% 2. Acquire complex IQ samples.
% 3. Monitor frame validity and overflows.
% 4. Inspect signal magnitude, I/Q and PSD.
% 5. Save IQ data and acquisition diagnostics.

clear;
clc;
close all;

%% 1. Configuration

fc = 1090e6;
Fs = 5e6;

frameSize = 500000;  % 100 ms
numFrames = 50;      % 5 seconds at 100 ms per frame

captureDuration = frameSize*numFrames/Fs;

%% 2. Configure Pluto receiver

rx = sdrrx('Pluto', ...
    'RadioID', 'usb:0', ...
    'CenterFrequency', fc, ...
    'BasebandSampleRate', Fs, ...
    'SamplesPerFrame', frameSize, ...
    'GainSource', 'AGC Slow Attack', ...
    'OutputDataType', 'double', ...
    'ShowAdvancedProperties', true);

% Enable hardware corrections

rx.EnableRFDCCorrection = true;
rx.EnableBasebandDCCorrection = true;
rx.EnableQuadratureCorrection = true;

%% 3. Acquire IQ samples

try

    % Display actual radio configuration

    radioInfo = info(rx);
    disp(radioInfo);

    % Discard first frame (startup transient)

    disp('Initializing receiver...');
    [~, ~, ~] = rx();

    % Allocate memory

    data = complex(zeros(frameSize*numFrames,1));

    % Store individual frame diagnostics

    overflowFrames = false(numFrames,1);
    validFrames = false(numFrames,1);

    disp('Starting IQ acquisition...');

    for k = 1:numFrames

        [frame, dataValid, overflow] = rx();

        % Store IQ samples

        idx = (k-1)*frameSize + (1:frameSize);
        data(idx) = frame;

        % Store diagnostic flags

        overflowFrames(k) = logical(overflow);
        validFrames(k) = logical(dataValid);

        fprintf('Frame %d/%d | Valid: %d | Overflow: %d\n', ...
            k, numFrames, validFrames(k), overflowFrames(k));

    end

catch ME

    release(rx);
    rethrow(ME);

end

% Release Pluto

release(rx);

%% 4. Acquisition information

overflowCount = sum(overflowFrames);
invalidFrameCount = sum(~validFrames);

fprintf('\n========== ACQUISITION RESULTS ==========\n');

fprintf('Number of samples: %d\n', length(data));
fprintf('Requested sampling rate: %.2f MS/s\n', Fs/1e6);
fprintf('Actual sampling rate: %.6f MS/s\n', ...
    radioInfo.BasebandSampleRate/1e6);
fprintf('Duration: %.3f seconds\n', captureDuration);

fprintf('Overflow frames: %d/%d\n', ...
    overflowCount, numFrames);

fprintf('Invalid frames: %d/%d\n', ...
    invalidFrameCount, numFrames);

fprintf('\n========== IQ STATISTICS ==========\n');

I = real(data);
Q = imag(data);
A = abs(data);

fprintf('Mean I: %.8f\n', mean(I));
fprintf('Mean Q: %.8f\n', mean(Q));

fprintf('Maximum |I|: %.6f\n', max(abs(I)));
fprintf('Maximum |Q|: %.6f\n', max(abs(Q)));

fprintf('Maximum amplitude: %.6f\n', max(A));
fprintf('Mean amplitude: %.6f\n', mean(A));
fprintf('Mean power: %.8f\n', mean(A.^2));

% Check for samples close to the component limits

limitThreshold = 0.99;

fprintf('Samples with |I| >= %.2f: %d\n', ...
    limitThreshold, sum(abs(I) >= limitThreshold));

fprintf('Samples with |Q| >= %.2f: %d\n', ...
    limitThreshold, sum(abs(Q) >= limitThreshold));

fprintf('====================================\n');

%% 5. Time vector

t = (0:length(data)-1)/Fs;

%% 6. Signal magnitude - First 5 ms

N = min(round(5e-3*Fs), length(data));

figure;

plot(t(1:N)*1e3, A(1:N));

xlabel('Time (ms)');
ylabel('|r[n]|');
title('Received Signal Magnitude - First 5 ms');
grid on;

%% 7. I and Q components

N_IQ = min(2000, length(data));

figure;

subplot(2,1,1);

plot(t(1:N_IQ)*1e3, I(1:N_IQ));

ylabel('I amplitude');
title('In-phase component');
grid on;

subplot(2,1,2);

plot(t(1:N_IQ)*1e3, Q(1:N_IQ));

xlabel('Time (ms)');
ylabel('Q amplitude');
title('Quadrature component');
grid on;

%% 8. Power spectral density

figure;

pwelch(data, [], [], [], Fs, 'centered');

title('Received Signal - Power Spectral Density');
xlabel('Frequency (Hz)');
grid on;

%% 9. Full capture magnitude

figure;

plot(t, A);

xlabel('Time (s)');
ylabel('|r[n]|');
title('Received Signal Magnitude - Full Capture');
grid on;

%% 10. Zoom into first candidate event

% Approximate event location from previous capture

t_start_1 = 0.85e-3;
t_end_1 = 0.95e-3;

idx_start = max(1, round(t_start_1*Fs) + 1);
idx_end = min(length(data), round(t_end_1*Fs) + 1);

idx = idx_start:idx_end;

figure;

plot(t(idx)*1e6, A(idx), '-o');

xlabel('Time (\mus)');
ylabel('|r[n]|');
title('Zoom - First Candidate Event');
grid on;

%% 11. Zoom into second candidate event

t_start_2 = 2.00e-3;
t_end_2 = 2.10e-3;

idx_start = max(1, round(t_start_2*Fs) + 1);
idx_end = min(length(data), round(t_end_2*Fs) + 1);

idx = idx_start:idx_end;

figure;

plot(t(idx)*1e6, A(idx), '-o');

xlabel('Time (\mus)');
ylabel('|r[n]|');
title('Zoom - Second Candidate Event');
grid on;

%% 12. Save IQ data and diagnostics

% Locate project directory

scriptFolder = fileparts(mfilename('fullpath'));

if isempty(scriptFolder)
    scriptFolder = pwd;
end

% Create data folder

dataFolder = fullfile(scriptFolder, 'data');

if ~exist(dataFolder, 'dir')
    mkdir(dataFolder);
end

% Save capture

outputFile = fullfile(dataFolder, 'adsb_capture.mat');

save(outputFile, ...
    'data', ...
    'Fs', ...
    'fc', ...
    'radioInfo', ...
    'frameSize', ...
    'numFrames', ...
    'captureDuration', ...
    'overflowFrames', ...
    'validFrames', ...
    'overflowCount', ...
    'invalidFrameCount');

fprintf('\nIQ data saved successfully:\n%s\n', outputFile);

%% 13. Final acquisition status

if overflowCount == 0 && invalidFrameCount == 0

    disp('Acquisition status: ALL FRAMES VALID');

elseif overflowCount > 0

    disp('Acquisition status: OVERFLOWS DETECTED');

else

    disp('Acquisition status: INVALID FRAMES DETECTED');

end





