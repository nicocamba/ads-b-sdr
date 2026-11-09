
%% 05_crc_validation.m
% ADS-B Receiver - Mode S CRC Validation
%
% Input:
%   data/adsb_demodulated_messages.mat
%
% Output:
%   data/adsb_valid_messages.mat

clear;
clc;
close all;

%% 1. Load demodulated messages

scriptFolder = fileparts(mfilename('fullpath'));
dataFolder = fullfile(scriptFolder, 'data');

inputFile = fullfile(dataFolder, ...
    'adsb_demodulated_messages.mat');

outputFile = fullfile(dataFolder, ...
    'adsb_valid_messages.mat');

load(inputFile);

fprintf('\n====================================\n');
fprintf('       ADS-B CRC VALIDATION\n');
fprintf('====================================\n');

%% 2. Configuration

messageLength = 112;
headerLength = 88;
crcLength = 24;

polynomial = uint32(hex2dec('FFF409'));

numCandidates = size(demodulatedBits, 1);

% Results
crcValid = false(numCandidates, 1);
dfValues = zeros(numCandidates, 1);
icaoAddresses = strings(numCandidates, 1);
crcRemainders = zeros(numCandidates, 1);

%% 3. Process each candidate

for k = 1:numCandidates

    bits = double(demodulatedBits(k, :));

    % Check message length
    if numel(bits) ~= messageLength
        continue;
    end

    % Check that all bits are binary
    if any(bits ~= 0 & bits ~= 1)
        continue;
    end

    %% Extract Downlink Format (DF)

    dfValues(k) = bi2de(bits(1:5), 'left-msb');

    % We focus on ADS-B Extended Squitter (DF17)
    if dfValues(k) ~= 17
        continue;
    end

    %% Extract ICAO address

    icaoBits = bits(9:32);

    icaoValue = bi2de(icaoBits, 'left-msb');

    icaoAddresses(k) = upper(string(dec2hex(icaoValue, 6)));

    %% Calculate CRC syndrome

    remainder = uint32(0);

    for i = 1:headerLength

        inputBit = uint32(bits(i));

        feedback = bitget(remainder, 24);

        remainder = bitand(bitshift(remainder, 1), ...
                           uint32(hex2dec('FFFFFF')));

        if bitxor(inputBit, uint32(feedback))
            remainder = bitxor(remainder, polynomial);
        end

    end

    % Append received parity bits to the CRC calculation
    for i = headerLength+1:messageLength

        inputBit = uint32(bits(i));

        feedback = bitget(remainder, 24);

        remainder = bitand(bitshift(remainder, 1), ...
                           uint32(hex2dec('FFFFFF')));

        if bitxor(inputBit, uint32(feedback))
            remainder = bitxor(remainder, polynomial);
        end

    end

    crcRemainders(k) = double(remainder);

    % DF17 carries direct CRC parity (no address overlay).
    % A valid 112-bit frame has a zero remainder.
    crcValid(k) = (remainder == uint32(0));

end

%% 4. Display results

fprintf('\nTotal candidates: %d\n', numCandidates);

fprintf('DF17 candidates: %d\n', sum(dfValues == 17));

fprintf('CRC-valid messages: %d\n', sum(crcValid));

fprintf('CRC-invalid messages: %d\n', ...
    sum(dfValues == 17 & ~crcValid));

fprintf('\n------------------------------------\n');

for k = 1:numCandidates

    if dfValues(k) == 17

        fprintf('Candidate %d | ICAO: %s | Syndrome: %06X | ', ...
            k, icaoAddresses(k), uint32(crcRemainders(k)));

        if crcValid(k)
            fprintf('VALID\n');
        else
            fprintf('INVALID\n');
        end

    else

        fprintf('Candidate %d | DF: %d | Not DF17\n', ...
            k, dfValues(k));

    end

end

%% 5. Save valid messages and metadata

validCandidateIndices = find(crcValid);

validBits = demodulatedBits(validCandidateIndices, :);

validICAO = icaoAddresses(validCandidateIndices);

validDetectionTimes = detectionTimes(validCandidateIndices);

% Preserve demodulation confidence, if available
if exist('bitConfidence', 'var')
    validBitConfidence = bitConfidence(validCandidateIndices, :);
else
    validBitConfidence = [];
end

% Preserve first- and second-half energies, if available
if exist('firstHalfEnergy', 'var')
    validFirstHalfEnergy = firstHalfEnergy(validCandidateIndices, :);
else
    validFirstHalfEnergy = [];
end

if exist('secondHalfEnergy', 'var')
    validSecondHalfEnergy = secondHalfEnergy(validCandidateIndices, :);
else
    validSecondHalfEnergy = [];
end

save(outputFile, ...
    'validBits', ...
    'validICAO', ...
    'validDetectionTimes', ...
    'validCandidateIndices', ...
    'validBitConfidence', ...
    'validFirstHalfEnergy', ...
    'validSecondHalfEnergy', ...
    'crcValid', ...
    'dfValues', ...
    'icaoAddresses', ...
    'crcRemainders', ...
    'Fs', ...
    'fc');

fprintf('\nSaved %d valid messages to:\n%s\n', ...
    size(validBits, 1), outputFile);




