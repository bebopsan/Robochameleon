% Run a simple coherent transmission example as a script
%
% This is a simple "back-to-back" setup with no channel.
%
% This scrip uses a model of single polarization QPSK coherent detection.
% The state of polarization of the LO is assumed to be aligned with the
% signal. 
% The idea is to explore the effects of lasers linewidth and OSNR on the 
% BER  before and after using phase synchronization algorithms.
%
% The phase synchronization algorithm is the 4th power method and has been 
% implemented as a module called VITERBI_CPR_v1.m.
%

%Initialize

%% General Parameters
robochameleon;
setpref('robochameleon', 'debugMode', 1)        %make sure unit outputs will be available to view

clearall
close all

%MAIN CONTROLS
M = 4;     %modulation order
Rs = 28e9;  %symbol rate
L = 2^13-1;   %sequence length
linewidth = 1e5;
OSNR = 20;
%% DSO_v1 definition
% param.dso.only=2;
param.dso.maxlength=1e4;
param.dso.enable=1;
param.dso.mode = 'coherent';
param.dso.nInputs = 1;
dso = DSO_v1(param.dso);

param.cb.nInputs = 2;
param.cb.type = 'simple';
Combiner_simple = Combiner_v1(param.cb);

%% Signal definition
constType='QAM';
constellation = constref(constType, M);

Fs_dso = 80e9;
Fs = 4*Rs;
Fc =193.625e12;

% PULSE PATTERN GENERATOR
param.ppg = struct('order', 15, 'total_length', L, 'Rs', Rs, 'nOutputs', 1, 'levels', [-1 1]);
ppg = PPG_v1(param.ppg);
sig_x_c = ppg.traverse();

% DELAY AND NEGATE
delay1  = Delay_v1(1);
sig_x_s = delay1.traverse(sig_x_c);
sig_x_c = sig_x_c.fun1(@(x) - x);

% PULSE SHAPING
param.ps.samplesPerSymbol = 16;
param.ps.pulseShape       = 'rz33';
param.ps.symbolRate       = Rs;
ps = PulseShaper_v1(param.ps);

sig_x_c_us = ps.traverse(sig_x_c);
sig_x_s_us = ps.traverse(sig_x_s);

%% Scopes on the transmitted signals 
% dso.traverse(Combiner_simple.traverse(sig_x_c,sig_x_s));
% name = [get(gcf,'name'),': Transmitted signal after upsampling'];
% set(gcf,'name',name)
% dso.traverse(Combiner_simple.traverse(sig_x_c_us,sig_x_s_us));
% name = [get(gcf,'name'),': Transmitted signal after upsampling'];
% set(gcf,'name',name)

decimator = Decimate_v1(struct('Nss',1,'draw',0));

%% LASER DEFINITION AND MODULATION
param.laser = struct('Power', pwr(30, {5, 'dBm'}), 'linewidth', linewidth, ...
    'Fs', param.ppg.Rs*param.ps.samplesPerSymbol, 'Rs', Rs, 'Fc', Fc, ...
    'Lnoise', param.ps.samplesPerSymbol*L, 'L', L);
laser       = Laser_v1(param.laser);
sig_laser   = laser.traverse();
param.iq    = struct('mode','simple');
iq          = IQ_single_pol_v1(param.iq);

sig_x     = iq.traverse(sig_x_c_us, sig_x_s_us, sig_laser);

%% Scope on optical signal after transmitter laser.
% dso.traverse(Combiner_simple.traverse(sig_x.fun1(@(x) real(x)),sig_x.fun1(@(x) imag(x))));
% name = [get(gcf,'name'),': Transmitted signal after laser'];
% set(gcf,'name',name)

%% Channel noise
param.SNR.OSNR = OSNR;
snr = OSNR_v1(param.SNR);
sig_x = snr.traverse(sig_x);

%% COHERENT FRONT END
% foffset = 3e6;
foffset = 0e3;
LOparam = struct('Power', pwr(30, {5, 'dBm'}), 'linewidth', linewidth, 'Fc', Fc+foffset);
param.coh.LO = LOparam;
param.coh.draw = 0;
param.coh.hyb.phase_angle = pi/2;
BPDparam = struct('R', 1,'f3dB', 4*Rs,'Rtherm', 50);
param.coh.bpd = BPDparam;

cfe = CoherentFrontend_single_pol_v1(param.coh);
[I, Q] = cfe.traverse(sig_x);

IQ = Combiner_simple.traverse(I, Q);

dso.traverse(IQ);
name = [get(gcf,'name'),': Transmitted signal after coherent front end'];
set(gcf,'name',name)

param.cb2.nInputs = 2;
param.cb2.type    = 'complex';
Combiner_complex  = Combiner_v1(param.cb2);

%% Carrier recovery using Viterbi and Viterbi phase equalization

param.cpr.vv = struct('N', 10,'draw',1');
cpr = VITERBI_CPR_v1(param.cpr.vv);
decoded_symb = cpr.traverse(decimator.traverse(I),decimator.traverse(Q));
dec_symbs = decoded_symb.getRaw+1;
p = params(decoded_symb);
decoded_IQ = signal_interface(exp(1j.*(dec_symbs-1+1/2)*2*pi/4),p);

%% BER TESTER
sig_x     = Combiner_complex.traverse(sig_x_c.fun1(@(x) - x), sig_x_s.fun1(@(x) - x));
T         = round((angle(get(sig_x))-(pi/4))/(pi/2));
sig_diff  = uint16(mod(T(2:end)-T(1:(end-1)),4))+1; 
sig_bits  = Combiner_simple.traverse(sig_x_c.fun1(@(x) - x), sig_x_s.fun1(@(x) - x));
bits = get(sig_bits);
bits(bits==-1) =0;
symbs = uint16(mod(T,4))+1;

param.bert = struct('M', M, 'dimensions', 1,'ConstType','QAM', 'coding', 'bin', 'PostProcessMethod', 'none','DecisionType', 'hard');
param.bert_prbs = struct('M', M, 'dimensions', 1,'ConstType','QAM', 'coding', 'bin','prbs', gen_prbs(15),'PostProcessMethod', 'none','DecisionType', 'hard');
bert = BERT_v1(param.bert);
bert_prbs = BERT_v1(param.bert_prbs);

IQ = Combiner_complex.traverse(decimator.traverse(I), decimator.traverse(Q));

phase_noise = zeros(L,1);
% Center elements of each block of size 2*N+1.
blck_indx_vec =  (1:cpr.n_blcks)*(2*cpr.N+1)-cpr.N; 
blck_indx = 1;
for blck_cntr = blck_indx_vec
    blck = (blck_cntr-cpr.N):(blck_cntr+cpr.N);
    phase_noise(blck) = cpr.phase_x(blck_indx);
    blck_indx = blck_indx+1;
end

bert_prbs.traverse(IQ);
name = [get(gcf,'name'),': Before phase correction'];
set(gcf,'name',name)

IQ = signal_interface(IQ.getRaw.*exp(-1j*phase_noise),p);

lut  = [4,3,1,2];
[~,symb_range] = findrange(sig_diff);
for i=max(1,symb_range.min):symb_range.max
    idx = sig_diff==i; % Find indices for all symbols i
    symb(idx) = repmat(lut(i),1,nnz(idx)); % Take value from the LUT
end
symb = uint16(symb);
bert.traverse(decoded_IQ,symb');
name = [get(gcf,'name'),': After phase correction using symbs'];
set(gcf,'name',name)

bert_prbs.traverse(IQ);
bert_prbs.traverse(decoded_IQ);
name = [get(gcf,'name'),': After phase correction using PRBS'];
set(gcf,'name',name)


