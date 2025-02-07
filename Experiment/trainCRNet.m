function [net,mu,sig,XrAll] = trainCRNet(data_store,lag_interval)

%% OPTIONS ================================================================
Lag = lag_interval;         % How many obs to look back
% horizon = 50;               % horizon forecasting to be use in the beyong horizon section
MiniBatchSize = 64;         % MiniBatchSize
MaxEpochs = 1;              % MaxEpochs
learningrate = 0.00611;     % Learning rate
solver = "adam";            % solver option

%% LOAD DATA ==============================================================
[~,y] = data_store.getmats('all','imp','time');
[~,y_train] = data_store.getmats('train','imp','time');

mu = mean(y_train);
sig = std(y_train);
y_train_std = (y_train - mu) / sig;
y_std = (y - mu) / sig;

%% PREPARE VARIABLES ======================================================
% use cell array to get ready the data sequence -> Last

% Training data
XTrain = lagmatrix(y_train_std,Lag);
XTrain = XTrain(max(Lag)+1:end,:)';
YTrain = y_train_std(max(Lag)+1:end)';
XrTrain = cell(size(XTrain,2),1);
YrTrain = zeros(size(YTrain,2),1);
for i=1:size(XTrain,2)
    XrTrain{i,1} = XTrain(:,i);
    YrTrain(i,1) = YTrain(:,i);
end

% All data
XAll = lagmatrix(y_std,Lag);
XAll = XAll(max(Lag)+1:end,:)';
YAll = y_std(max(Lag)+1:end)';
XrAll = cell(size(XAll,2),1);
YrAll = zeros(size(YAll,2),1);
for i=1:size(XAll,2)
    XrAll{i,1} = XAll(:,i);
    YrAll(i,1) = YAll(:,i);
end

%% NETWORK ARCHITECTURE ===================================================
numFeatures = size(XTrain,1);% it depends on the roll back window (No of features, one output)
numResponses = 1;FiltZise = 5;
% you can follow this template and create your own Architecture
layers = [...
    % Here input the sequence. No need to be modified
    sequenceInputLayer([numFeatures 1 1],'Name','input')
    sequenceFoldingLayer('Name','fold')
    
    % from here do your engeneering design of your CNN feature
    % extraction
    convolution2dLayer(FiltZise,32,'Padding','same','WeightsInitializer','he','Name','conv','DilationFactor',1);
    batchNormalizationLayer('Name','bn')
    eluLayer('Name','elu')
    convolution2dLayer(FiltZise,32,'Padding','same','WeightsInitializer','he','Name','conv1','DilationFactor',2);
    eluLayer('Name','elu1')
    convolution2dLayer(FiltZise,32,'Padding','same','WeightsInitializer','he','Name','conv2','DilationFactor',4);
    eluLayer('Name','elu2')
    convolution2dLayer(FiltZise,32,'Padding','same','WeightsInitializer','he','Name','conv3','DilationFactor',8);
    eluLayer('Name','elu3')
    convolution2dLayer(FiltZise,32,'Padding','same','WeightsInitializer','he','Name','conv4','DilationFactor',16);
    eluLayer('Name','elu4')
    averagePooling2dLayer(1,'Stride',FiltZise,'Name','pool1')
    
    % here you finish your CNN design and next step is to unfold and
    % flatten. Keep this part like this
    sequenceUnfoldingLayer('Name','unfold')
    flattenLayer('Name','flatten')
    
    % from here the RNN design. Feel free to add or remove layers
    gruLayer(128,'Name','gru1','RecurrentWeightsInitializer','He','InputWeightsInitializer','He')
    lstmLayer(64,'Name','gru2','RecurrentWeightsInitializer','He','InputWeightsInitializer','He')
    dropoutLayer(0.25,'Name','drop2')
    % this last part you must change the outputmode to last
    lstmLayer(32,'OutputMode',"last",'Name','bil4','RecurrentWeightsInitializer','He','InputWeightsInitializer','He')
    dropoutLayer(0.25,'Name','drop3')
    % here finish the RNN design
    
    % use a fully connected layer with one neuron because you will predict one step ahead
    fullyConnectedLayer(numResponses,'Name','fc')
    regressionLayer('Name','output')    ];

layers = layerGraph(layers);
layers = connectLayers(layers,'fold/miniBatchSize','unfold/miniBatchSize');

%% TRAINING OPTIONS =======================================================
if gpuDeviceCount>0
    mydevice = 'gpu';
else
    mydevice = 'cpu';
end
options = trainingOptions...
(...
    solver, ...
    'MaxEpochs',            MaxEpochs, ...
    'GradientThreshold',    1, ...
    'InitialLearnRate',     learningrate, ...
    'LearnRateSchedule',    "piecewise", ...
    'LearnRateDropPeriod',  96, ...
    'LearnRateDropFactor',  0.25, ...
    'MiniBatchSize',        MiniBatchSize,...
    'Verbose',              false, ...
    'Shuffle',              "every-epoch",...
    'ExecutionEnvironment', mydevice,...
    'Plots',                'training-progress');

%% TRAIN NETWORK (MAY TAKE A WHILE...) ====================================
% rng(0);
net = trainNetwork(XrTrain,YrTrain,layers,options);






