function [Y,Xf,Af] = nnFunction(X,~,~)
%MYNEURALNETWORKFUNCTION neural network simulation function.
%
% Auto-generated by MATLAB, 10-Apr-2022 22:18:50.
%
% [Y] = myNeuralNetworkFunction(X,~,~) takes these arguments:
%
%   X = 1xTS cell, 1 inputs over TS timesteps
%   Each X{1,ts} = Qx2 matrix, input #1 at timestep ts.
%
% and returns:
%   Y = 1xTS cell of 1 outputs over TS timesteps.
%   Each Y{1,ts} = Qx1 matrix, output #1 at timestep ts.
%
% where Q is number of samples (or series) and TS is the number of timesteps.

%#ok<*RPMT0>

% ===== NEURAL NETWORK CONSTANTS =====

% Input 1
x1_step1.keep = 2;
x1_step2.xoffset = 737791.000590278;
x1_step2.gain = 0.00271893200854225;
x1_step2.ymin = -1;

% Layer 1
b1 = [-3.5590010675022560882;23.219756391043492982;14.042822697190286974;5.1081542078014852137;3.2077409778582035571;-3.3295442783364603834;-3.8947835277806905907;3.6790886371146722666;19.32495964364170149;13.190336558297001801];
IW1_1 = [-0.92741182827183277215;-25.097954013627916225;-23.545975601593490012;-14.636718187238738409;-15.183056359866982987;-9.2890263339866354642;-11.697686821607806706;9.1006414954143508567;24.587573061419885079;16.99843501021256742];

% Layer 2
b2 = 1.6065157904234541597;
LW2_1 = [2.3272658186725889706 0.07219064155976293029 -0.045028765585386369696 -0.0056663860806069107218 -0.064247072302974730929 6.0431280197355921047 -3.3274331143446138626 2.7185217959186660508 -0.38190872022796734653 0.32474359276274750163];

% Output 1
y1_step1.ymin = -1;
y1_step1.gain = 0.00343053173241852;
y1_step1.xoffset = -18;

% ===== SIMULATION ========

% Format Input Arguments
isCellX = iscell(X);
if ~isCellX
    X = {X};
end

% Dimensions
TS = size(X,2); % timesteps
if ~isempty(X)
    Q = size(X{1},1); % samples/series
else
    Q = 0;
end

% Allocate Outputs
Y = cell(1,TS);

% Time loop
for ts=1:TS
    
    % Input 1
    X{1,ts} = X{1,ts}';
    temp = removeconstantrows_apply(X{1,ts},x1_step1);
    Xp1 = mapminmax_apply(temp,x1_step2);
    
    % Layer 1
    a1 = tansig_apply(repmat(b1,1,Q) + IW1_1*Xp1);
    
    % Layer 2
    a2 = repmat(b2,1,Q) + LW2_1*a1;
    
    % Output 1
    Y{1,ts} = mapminmax_reverse(a2,y1_step1);
    Y{1,ts} = Y{1,ts}';
end

% Final Delay States
Xf = cell(1,0);
Af = cell(2,0);

% Format Output Arguments
if ~isCellX
    Y = cell2mat(Y);
end
end

% ===== MODULE FUNCTIONS ========

% Map Minimum and Maximum Input Processing Function
function y = mapminmax_apply(x,settings)
y = bsxfun(@minus,x,settings.xoffset);
y = bsxfun(@times,y,settings.gain);
y = bsxfun(@plus,y,settings.ymin);
end

% Remove Constants Input Processing Function
function y = removeconstantrows_apply(x,settings)
y = x(settings.keep,:);
end

% Sigmoid Symmetric Transfer Function
function a = tansig_apply(n,~)
a = 2 ./ (1 + exp(-2*n)) - 1;
end

% Map Minimum and Maximum Output Reverse-Processing Function
function x = mapminmax_reverse(y,settings)
x = bsxfun(@minus,y,settings.ymin);
x = bsxfun(@rdivide,x,settings.gain);
x = bsxfun(@plus,x,settings.xoffset);
end
