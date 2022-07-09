%% ======================================================================== FULL DATA SET (288 obs per day) ===================
load FULL_IMPUTED.mat
ds_full = NedocData(TI_full,288);
ds_full = ds_full.setToday(0.95);
ds_full = ds_full.setPPD(48);

%% ======================================================================== DAY CURVE TRANSFORM ===============================
% getmats
[~,yimp] = ds_full.getmats('all','time');
ppd = ds_full.PPD;

x = (1:ppd)';
y = zeros([ds_full.L/ppd,ppd]);
for i = 1:ppd:length(yimp)-(ppd-1)
    y((i+(ppd-1))/ppd,:) = yimp(i:i+(ppd-1));
end

% fits
transform = [x.^0,...
    sin(x*2*pi/ppd), cos(x*2*pi/ppd),...
    sin(x*2*pi/(ppd/2)), cos(x*2*pi/(ppd/2)),...
    sin(x*2*pi/(ppd/4)), cos(x*2*pi/(ppd/4)),...
    sin(x*2*pi/(ppd/8)), cos(x*2*pi/(ppd/8))     ];
y_trans = zeros([size(y,1),size(transform,2)]);

for i = 1:size(y,1)
    y_trans(i,:) = normalEqn(transform,y(i,:)');
end

% view transform
transformed_y = y_trans * transform';
y_prediction = reshape(transformed_y', [], 1);
ds_full = ds_full.pushResp(y_prediction,'trans');
[~,avgacc] = ds_full.plot('View Transform', 'tmr-3', 9)                       %#ok<ASGLU,NOPTS>
    ds_full = ds_full.popResp;

%% ======================================================================== TRAIN ARCRIN ======================================
M = height(ds_full.T_imp) / ppd;
lags = 1:7;
[crnet, mu, sig, transform, Xcell] = trainARCRIN(ds_full, lags, 100);         % Xr is standardized lag matrix

%% ======================================================================== PREDICT, PLOT, AND ASSESS =========================
coeff_pred_std = predict( crnet, Xcell, "ExecutionEnvironment",'gpu', "MiniBatchSize",max(lags)*size(transmat,2) );
coeff_pred_std = cast(coeff_pred_std,"double");
coeff_pred_std = [zeros([M-size(coeff_pred_std,1) , size(coeff_pred_std,2)]) ; coeff_pred_std];
coeff_pred = sig .* coeff_pred_std + mu;

daypred = coeff_pred * transform';
y_prediction = reshape(daypred', [], 1);

ds_full = ds_full.pushResp(y_prediction);
[~,avgacc] = ds_full.plot('Predictions', 'tmr', 9)                   %#ok<NOPTS>



