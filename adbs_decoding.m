
%% ============================================================
%  ADS-B RECEIVER
%  SCRIPT 06: MODE S MESSAGE DECODING
%
%  Input:
%       data/adsb_valid_messages.mat
%
%  Output:
%       data/aircraft_data.mat
%
%  Supported messages:
%       TC 1-4   Aircraft identification
%       TC 5-8   Surface position
%       TC 9-18  Airborne position (barometric altitude)
%       TC 19    Airborne velocity
%       TC 20-22 Airborne position (GNSS altitude)
%
% =============================================================

clear;
clc;
close all;

%% 1. LOAD VALID MESSAGES

scriptFolder = fileparts(mfilename('fullpath'));
dataFolder = fullfile(scriptFolder, 'data');

inputFile = fullfile(dataFolder, ...
    'adsb_valid_messages.mat');

outputFile = fullfile(dataFolder, ...
    'aircraft_data.mat');

if ~isfile(inputFile)
    error('Input file not found: %s', inputFile);
end

load(inputFile);

numMessages = size(validBits, 1);

fprintf('\n');
fprintf('====================================================\n');
fprintf('              ADS-B MESSAGE DECODER\n');
fprintf('====================================================\n');

fprintf('Valid messages loaded: %d\n', numMessages);

%% 2. INITIALIZE OUTPUT

aircraftData = cell(numMessages, 1);

%% 3. DECODE MESSAGES

for k = 1:numMessages

    bits = double(validBits(k, :));

    fprintf('\n');
    fprintf('====================================================\n');
    fprintf('MESSAGE %d\n', k);
    fprintf('====================================================\n');

    if numel(bits) ~= 112 || any(bits ~= 0 & bits ~= 1)
        fprintf('Invalid message structure.\n');
        continue;
    end

    %% 3.1 General Mode S fields

    DF = bi2de(bits(1:5), 'left-msb');
    CA = bi2de(bits(6:8), 'left-msb');

    ICAOValue = bi2de(bits(9:32), 'left-msb');
    ICAO = upper(dec2hex(ICAOValue, 6));

    ME = bits(33:88);

    TC = bi2de(ME(1:5), 'left-msb');

    info = struct();

    info.DF = DF;
    info.CA = CA;
    info.ICAO = ICAO;
    info.TypeCode = TC;
    info.RawBits = bits;

    if exist('validDetectionTimes', 'var')
        info.DetectionTime = validDetectionTimes(k);
    end

    fprintf('DF: %d\n', DF);
    fprintf('CA: %d\n', CA);
    fprintf('ICAO: %s\n', ICAO);
    fprintf('Type Code: %d\n', TC);

    if isfield(info, 'DetectionTime')
        fprintf('Reception time: %.6f s\n', ...
            info.DetectionTime);
    end

    %% 3.2 Aircraft identification: TC 1-4

    if TC >= 1 && TC <= 4

        category = bi2de(ME(6:8), 'left-msb');

        callsign = decodeCallsign(ME(9:56));

        info.Category = category;
        info.Callsign = callsign;

        fprintf('\n--- AIRCRAFT IDENTIFICATION ---\n');
        fprintf('Callsign: %s\n', callsign);
        fprintf('Category: %d\n', category);

    %% 3.3 Surface position: TC 5-8

    elseif TC >= 5 && TC <= 8

        movement = bi2de(ME(6:12), 'left-msb');

        trackStatus = ME(13);
        trackCode = bi2de(ME(14:20), 'left-msb');

        CPRFormat = ME(22);

        CPRLatitude = bi2de(ME(23:39), 'left-msb');
        CPRLongitude = bi2de(ME(40:56), 'left-msb');

        info.MovementCode = movement;
        info.TrackStatus = trackStatus;
        info.TrackCode = trackCode;

        info.CPRFormat = CPRFormat;
        info.CPRLatitude = CPRLatitude;
        info.CPRLongitude = CPRLongitude;

        fprintf('\n--- SURFACE POSITION ---\n');

        fprintf('Movement code: %d\n', movement);

        if trackStatus == 1
            track = trackCode*360/128;
            info.TrackAngle = track;
            fprintf('Track angle: %.2f degrees\n', track);
        else
            info.TrackAngle = NaN;
            fprintf('Track angle: unavailable\n');
        end

        fprintf('CPR format: %d\n', CPRFormat);
        fprintf('CPR latitude: %d\n', CPRLatitude);
        fprintf('CPR longitude: %d\n', CPRLongitude);

    %% 3.4 Airborne position: TC 9-18 and TC 20-22

    elseif (TC >= 9 && TC <= 18) || (TC >= 20 && TC <= 22)

        altitudeBits = ME(9:20);

        if TC >= 20
            altitudeSource = 'GNSS geometric altitude';
            altitude = decodeGNSSAltitude(altitudeBits);
        else
            altitudeSource = 'Barometric altitude';
            altitude = decodeBarometricAltitude(altitudeBits);
        end

        timeFlag = ME(21);
        CPRFormat = ME(22);

        CPRLatitude = bi2de(ME(23:39), 'left-msb');
        CPRLongitude = bi2de(ME(40:56), 'left-msb');

        info.Altitude = altitude;
        info.AltitudeSource = altitudeSource;

        info.TimeFlag = timeFlag;
        info.CPRFormat = CPRFormat;

        info.CPRLatitude = CPRLatitude;
        info.CPRLongitude = CPRLongitude;

        fprintf('\n--- AIRBORNE POSITION ---\n');

        fprintf('Altitude source: %s\n', altitudeSource);

        if ~isnan(altitude)
            fprintf('Altitude: %.0f feet\n', altitude);
            fprintf('Altitude: %.1f metres\n', altitude*0.3048);
        else
            fprintf('Altitude: unavailable\n');
        end

        fprintf('Time flag: %d\n', timeFlag);

        if CPRFormat == 0
            fprintf('CPR format: EVEN\n');
        else
            fprintf('CPR format: ODD\n');
        end

        fprintf('CPR latitude: %d\n', CPRLatitude);
        fprintf('CPR longitude: %d\n', CPRLongitude);

    %% 3.5 Airborne velocity: TC 19

    elseif TC == 19

        subtype = bi2de(ME(6:8), 'left-msb');

        info.VelocitySubtype = subtype;

        fprintf('\n--- AIRBORNE VELOCITY ---\n');
        fprintf('Subtype: %d\n', subtype);

        % Vertical rate

        verticalRateSource = ME(37);
        verticalRateCode = bi2de(ME(38:46), 'left-msb');

        if verticalRateCode > 0

            verticalRate = (verticalRateCode - 1)*64;

            if verticalRateSource == 1
                verticalRate = -verticalRate;
            end

            info.VerticalRate = verticalRate;

            fprintf('Vertical rate: %.0f ft/min\n', ...
                verticalRate);

        else

            info.VerticalRate = NaN;
            fprintf('Vertical rate: unavailable\n');

        end

        % Ground velocity: subtypes 1 and 2

        if subtype == 1 || subtype == 2

            signEW = ME(14);
            valueEW = bi2de(ME(15:24), 'left-msb');

            signNS = ME(25);
            valueNS = bi2de(ME(26:35), 'left-msb');

            if valueEW > 0 && valueNS > 0

                scale = 1;

                if subtype == 2
                    scale = 4;
                end

                velocityEW = (valueEW - 1)*scale;
                velocityNS = (valueNS - 1)*scale;

                if signEW == 1
                    velocityEW = -velocityEW;
                end

                if signNS == 1
                    velocityNS = -velocityNS;
                end

                groundSpeed = hypot(velocityEW, velocityNS);

                trackAngle = mod( ...
                    atan2d(velocityEW, velocityNS), 360);

                info.EastWestVelocity = velocityEW;
                info.NorthSouthVelocity = velocityNS;

                info.GroundSpeed = groundSpeed;
                info.TrackAngle = trackAngle;

                fprintf('East-West velocity: %.1f knots\n', ...
                    velocityEW);

                fprintf('North-South velocity: %.1f knots\n', ...
                    velocityNS);

                fprintf('Ground speed: %.1f knots\n', ...
                    groundSpeed);

                fprintf('Ground speed: %.1f km/h\n', ...
                    groundSpeed*1.852);

                fprintf('Track angle: %.1f degrees\n', ...
                    trackAngle);

            else

                info.GroundSpeed = NaN;
                info.TrackAngle = NaN;

                fprintf('Ground speed: unavailable\n');

            end

        % Airspeed and heading: subtypes 3 and 4

        elseif subtype == 3 || subtype == 4

            headingStatus = ME(14);
            headingCode = bi2de(ME(15:24), 'left-msb');

            airspeedType = ME(25);
            airspeedCode = bi2de(ME(26:35), 'left-msb');

            if headingStatus == 1

                heading = headingCode*360/1024;

                info.Heading = heading;

                fprintf('Heading: %.1f degrees\n', heading);

            else

                info.Heading = NaN;
                fprintf('Heading: unavailable\n');

            end

            if airspeedCode > 0

                airspeed = (airspeedCode - 1);

                if subtype == 4
                    airspeed = airspeed*4;
                end

                info.Airspeed = airspeed;

                if airspeedType == 0
                    fprintf('Indicated airspeed: %.1f knots\n', ...
                        airspeed);
                else
                    fprintf('True airspeed: %.1f knots\n', ...
                        airspeed);
                end

            else

                info.Airspeed = NaN;
                fprintf('Airspeed: unavailable\n');

            end

        else

            fprintf('Velocity subtype not implemented.\n');

        end

    %% 3.6 Other ADS-B messages

    else

        fprintf('\nOther ADS-B message type.\n');
        fprintf('Type Code: %d\n', TC);

    end

    %% Save decoded message

    aircraftData{k} = info;

end

%% 4. SAVE RESULTS

save(outputFile, ...
    'aircraftData', ...
    'validBits', ...
    'validICAO', ...
    'validDetectionTimes', ...
    'Fs', ...
    'fc');

fprintf('\n');
fprintf('====================================================\n');
fprintf('              DECODING COMPLETED\n');
fprintf('====================================================\n');

fprintf('Messages decoded: %d\n', numMessages);

fprintf('Results saved to:\n%s\n', outputFile);


%% ============================================================
%  LOCAL FUNCTIONS
% =============================================================

function callsign = decodeCallsign(bits)

    characters = '';

    for j = 1:8

        charBits = bits((j-1)*6+1:j*6);

        value = bi2de(charBits, 'left-msb');

        % ADS-B character mapping

        if value >= 1 && value <= 26

            character = char('A' + value - 1);

        elseif value >= 48 && value <= 57

            character = char('0' + value - 48);

        elseif value == 32

            character = ' ';

        else

            character = ' ';

        end

        characters = [characters character]; %#ok<AGROW>

    end

    callsign = strtrim(characters);

end


function altitude = decodeBarometricAltitude(bits)

    % 12-bit AC12 field
    % Q=1: altitude in 25-ft increments

    Q = bits(8);

    if Q == 1

        Nbits = [bits(1:7), bits(9:12)];

        N = bi2de(Nbits, 'left-msb');

        altitude = 25*N - 1000;

    else

        % Q=0 requires Gillham/Gray-code decoding.
        % Not implemented in this version.

        altitude = NaN;

    end

end


function altitude = decodeGNSSAltitude(bits)

    % 12-bit geometric altitude field
    % Resolution: 25 feet

    N = bi2de(bits, 'left-msb');

    if N == 0

        altitude = NaN;

    else

        altitude = N*25 - 1000;

    end

end


