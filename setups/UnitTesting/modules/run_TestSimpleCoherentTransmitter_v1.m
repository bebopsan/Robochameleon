clearvars -except testFiles nn
close all

%% Parameters
% WaveformGenerator parameters
param.M                 = 4;
param.modulationFormat  = 'QAM';
param.N                 = 2;        % (not necessary)
param.samplesPerSymbol  = 16;
param.pulseShape        = 'rrc';
param.rollOff           = 0.2;

% DAC parameters
param.DACGaussianOrder     = 1;        % (not necessary)
param.DACGaussianBandwidth = 18e9;     % (not necessary)
param.DACBesselOrder         = 0;      % (not necessary)
param.DACBesselBandwidth     = 110e9;  % (not necessary)

param.outputVoltage     = 2.0;      % (not necessary)
param.amplitudeImbalance= 1;        % (not necessary)
param.skew              = [0.0 0.5];% (not necessary)
param.jitterVariance    = 1e-8;     % (not necessary)
param.upsamplingRate    = 2;        % (not necessary)
param.clockError        = 1e-6;     % (not necessary)

% Laser parameters - copies parameters from input signal
param.linewidth = 100e3;    % (not necessary)
param.Fs = 80e9;            % (not necessary)
param.Lnoise = 2^10;        % (not necessary)

% IQ modulator parameters

%% Create object
ct = SimpleCoherentTransmitter_v1(param);

%% Traverse object
out = ct.traverse();


