

classdef forecastModel
    
    properties
        
        % ========== TITLE ==========
        
        % title
        ttl;
        
        % ========== DATA ==========
        
        % numeric features
        dtNum                           % numeric date/time value (decimal part corresponds to time)
        date                            % numeric date value
        time                            % numeric time value
        month                           % month
        wkday                           % wkday
        
        % non-numeric features
        dtArr                           % dateTimeArray (as datetime object)
        wkdayNames                      % weekday names
        dtArr_Imp                       % imputed variants
        wkdayNames_Imp
        
        % target responses
        score                           % NEDOC Score (0-200)
        level                           % NEDOC Level (1-5)
        
        % symbolic values
        X                               % collected numeric features
        y                               % response value (score, we're not using classifiers since response is ordinal)
        X_train                         % training split of X
        X_test                          % testing split of X
        y_train                         % training split of y
        y_test                          % testing split of y
        
        % imputed symbolic values
        X_Imp                           % imputed data matrix
        y_Imp                           % imputed response vector
        X_train_Imp                     % training split of X
        X_test_Imp                      % testing split of X
        y_train_Imp                     % training split of y
        y_test_Imp                      % testing split of y
        
        % predicted responses
        score_pred                      % NEDOC Score (0-200)
        level_pred                      % NEDOC Level (1-5)
        
        % other sets
        avg_score_daily                 % set of averages for each day
        avg_level_daily                 % avg level for day
        
        % day type clustering
        X_clust_all                     % feature set for clustering (all)
        X_clust                         % feature set for clustering (training)
        dayClass                        % class for each day
        dayClass_DEF                    % class number <---> corresponding shape
        % classify clusters
        X_cl
        y_cl
        X_cl_train
        y_cl_train
        X_cl_test
        y_cl_test
        
        % ========== MODELING ============
        
        % forecast models
        mdl                             % model object
        trainFcn                        % training function
        predFcn                         % prediction function
        
        % split
        today                           % index of today (marks end of training set)
        tomorrow                        % index of tomorrow (marks beginning of testing set)
        tdimp                           % today for imputed set
        tmrimp                          % tmr for imputed set
        tdd                             % today for day set
        tmrd                            % tmr for day set
        
    end
    
    methods
        
        function this = forecastModel(TC,ttl,bias)   % ctor
            this.dtNum = TC.Date_Time;
            this.date = TC.Date;
            this.time = TC.Time;
            this.month = TC.Month;
            this.wkday = TC.Weekday;
            
            this.dtArr = TC.Date_Time_DTA;
            this.wkdayNames = TC.WKD_Name;
            
            this.score = TC.Score;
            this.level = TC.Level;
            
            this.ttl = ttl;
            
            this.avg_score_daily = this.fillDailyAvgs();
            this.avg_level_daily = getLevel(this.avg_score_daily);
            
            % X and y
            this.X = [this.date this.time this.wkday this.month];
            this.y = this.score;
            if bias
                this.X = [ones(size(this.date)) this.X];
            end
            
            % X and y IMPUTED
            y_NaN = [];
            i = 1;
            while i < length(this.date)
                [dayIdcs,dayLen] = this.getDay(i);
                [X_Imp_,dtArr_Imp_,wkdayNames_Imp_,y_NaN_] = this.saturate(dayIdcs);
                this.X_Imp = [this.X_Imp ; X_Imp_];
                this.dtArr_Imp = [this.dtArr_Imp ; dtArr_Imp_];
                this.wkdayNames_Imp = [this.wkdayNames_Imp ; wkdayNames_Imp_];
                y_NaN = [y_NaN ; y_NaN_]; %#ok<AGROW>
                i = i + dayLen;
            end
            this.y_Imp = fillHoles(y_NaN);
            
        end
        
        function this = rawModelInput(this,mdl)
            this.mdl = mdl;
        end
        
        function this = selectModelFunctions(this,trainingFcn,predictingFcn)
            if isa(trainingFcn,'function_handle')
                this.trainFcn = trainingFcn;
                this.predFcn = predictingFcn;
            else
                fprintf('inputs should be functions denoted with ''@''')
            end
        end
        
        function this = setSplit(this,td)
            [m,n] = size(this.X);
            [mi,~] = size(this.X_Imp);
            NB = 5-n;
            
            [idcs,~] = this.getDay(td);
            this.today = max(idcs);
            this.tomorrow = this.today+1;
            
            this.tdimp = find(this.X_Imp(:,2-NB)==this.date(this.today), 1, 'last' );
            this.tmrimp = this.tdimp+1;
            
            this.X_train = this.X(1:this.today,:);
            this.y_train = this.y(1:this.today);
            this.X_test = this.X(this.tomorrow:m,:);
            this.y_test = this.y(this.tomorrow:m);
            
            this.X_train_Imp = this.X_Imp(1:this.tdimp,:);
            this.y_train_Imp = this.y_Imp(1:this.tdimp);
            this.X_test_Imp = this.X_Imp(this.tmrimp:mi,:);
            this.y_test_Imp = this.y_Imp(this.tmrimp:mi);
            
        end
        
        function [idxList,dSz] = getDay(this,idx)
            [m,~] = size(this.wkday);
            
            if(idx > m)
                idx = m;
            end
            
            lowerBound = idx-60;
            upperBound = idx+60;
            
            if lowerBound < 1
                lowerBound = 1;
            end
            if upperBound > m
                upperBound = m;
            end
            
            wkd = this.wkday(idx);
            daySearchInterval = lowerBound:upperBound;
            
            idxList = find(this.wkday(daySearchInterval)==wkd);
            idxList = sort(idxList) + lowerBound - 1;
            [dSz,~] = size(idxList);
        end
        
        function [idxList,wSz] = getWeek(this,idx)
            [m,~] = size(this.wkday);
            
            i = idx;
            while this.wkday(i) ~= 1 && i > 1
                i=i-25;
            end
            
            if i > 1
                [list,sz] = this.getDay(i);
                startIdx = min(list);
            else
                [list,sz] = this.getDay(i+25);
                startIdx = 1;
            end
            
            i = list(1);
            
            while i < m && this.wkday(i) ~= 7
                i = i + sz;
                [~,sz] = this.getDay(i);
            end
            
            if i < m
                [list,sz] = this.getDay(i);
                endIdx = list(sz);
            else
                endIdx = m;
            end
            
            idxList = (startIdx:endIdx)';
            wSz = length(idxList);
        end
        
        function this = train(this)
            if isempty([this.today this.tomorrow])
                fprintf('must select split before training')
            else
                clear this.mdl
                this.mdl = this.trainFcn(this.X_train, this.y_train);
            end
        end
        
        function this = pred(this,external)
            if external
                
            else
                predictFcn = this.predFcn; %#ok<NASGU>
                this.score_pred = this.mdl.predictFcn(this.X);
                this.level_pred = getLevel(this.score_pred);
            end
        end
        
        function avgScore = fillDailyAvgs(this,varargin)
            [m,~] = size(this.date);
            
            for i = 1:2:length(varargin)
                if strcmp('PointsPerDay',varargin{i})
                    PPD = varargin{i+1};
                end
            end
            
            if nargin == 1
                avgScore = [];
                idcurr = 1;
                while idcurr < m
                    [dayIdcs,dayLen] = this.getDay(idcurr);
                    avgScore = [avgScore ; mean(this.score(dayIdcs))]; %#ok<AGROW>
                    idcurr = idcurr + dayLen;
                end
            elseif exist('PPD','var')
                avgScore = [];
                idcurr = 1;
                while idcurr < m
                    [dayIdcs,dayLen] = this.getDay(idcurr);
                    for i = 1:PPD
                        lb = cast(dayLen/PPD * (i-1) + 1, 'uint8');
                        ub = cast(dayLen/PPD * i, 'uint8');
                        PPDIdcs = dayIdcs(lb:ub);
                        avgScore = [avgScore ; mean(this.score(PPDIdcs))];
                        clear PPDIdcs
                    end
                    idcurr = idcurr + dayLen;
                end
            end
            
        end
        
        function [X48pt_,dtArr_,wkdayNames_,y48pt_NaN] = saturate(this,dayInterval,nppd)
            % function returns days as 48 point column vectors, filling in missing score values with NaN
            [~,n] = size(this.X);
            M = nppd;     % num of obs per day
            dayLen = length(dayInterval);
            
            % instantiate arrays
            timeArrIn = zeros([M,1]);
            timeArrIn(1:dayLen) = this.time(dayInterval);
            timeArrCorrected = (0:1/M:.99)';
            
            scoreArrOut = zeros([M,1]) + NaN;
            scoreArrOut(1:dayLen) = this.score(dayInterval);
            
            % fit data to 24 hour (48 points) day, leaving NaNs for missing values
            for i = 1:M
                if timeArrCorrected(i) >= timeArrIn(i)+.0001 || timeArrCorrected(i) <= timeArrIn(i)-.0001
                    timeArrIn(i:M) = circshift(timeArrIn(i:M),1);
                    scoreArrOut(i:M) = circshift(scoreArrOut(i:M),1);
                end
            end
            
            % x matrix
            if n==5
                X48pt_ = ones([M,n]);
                X48pt_(:,2) = X48pt_(:,2) * this.date(dayInterval(21));
                X48pt_(:,3) = timeArrCorrected;
                X48pt_(:,4) = X48pt_(:,4) * this.wkday(dayInterval(21));
                X48pt_(:,5) = X48pt_(:,5) * this.month(dayInterval(21));
            elseif n==4
                X48pt_ = ones([M,n]);
                X48pt_(:,1) = X48pt_(:,1) * this.date(dayInterval(21));
                X48pt_(:,2) = timeArrCorrected;
                X48pt_(:,3) = X48pt_(:,3) * this.wkday(dayInterval(21));
                X48pt_(:,4) = X48pt_(:,4) * this.month(dayInterval(21));
            end
            
            % non-numeric
            dtArr_ = this.dtArr(dayInterval(21)) + zeros([M,1]);
            wkdayNames_ = this.wkdayNames(dayInterval(21),:) + zeros([M,3]);
            
            % response
            y48pt_NaN = scoreArrOut;
        end
        
        function listOut = desaturate(this,listIn,nobias)
            XI = this.X_Imp;
            XO = this.X;
            mO = length(this.y);
            mI = length(listIn);
            
            for i = 1:mO
                while XI(i,3-nobias) <= XO(i,3-nobias) - 0.001 || XI(i,3-nobias) >= XO(i,3-nobias) + 0.001
                    XI(i:mI,:) = circshift(XI(i:mI,:),-1,1);
                    listIn(i:mI) = circshift(listIn(i:mI),-1,1);
                end
            end
            listOut = listIn(1:mO);
        end
        
        function this = createClusteringSet(this)
            M = 48;
            nd_all = length(this.y_Imp)/M;
            ndays = this.tdimp/M;                               % e.g. td = 25000 -> tdimp = 27600 -> 575 days in train set
            this.X_clust = zeros([ndays,M]);
            this.X_clust_all = zeros([nd_all,M]);
            for i = 0:nd_all-1
                this.X_clust_all(i+1,:) = this.y_Imp( (M*i+1):(M*(i+1)) );
                if i < ndays
                    this.X_clust(i+1,:) = this.y_Imp( (M*i+1):(M*(i+1)) );
                end
            end
        end
        
        function this = kmeansDayClusters(this,K)
            m = length(this.y);
            this = this.createClusteringSet;
            clList = kmeans(this.X_clust,K,'distance','sqeuclidean','Replicates',50);
            meanFork = zeros([K,48]);
            for k = 1:K
                kidcs = find(clList==k);
                meanFork(k,:) = mean(this.X_clust(kidcs,:),1);
            end
            
            this.dayClass = zeros([length(this.y_Imp)/48,1]);
            for i = 1:length(this.y_Imp)/48
                dists = pdist2(this.X_clust_all(i,:),meanFork,'squaredeuclidean');
                [~,this.dayClass(i)] = min(dists);
            end
            this.dayClass_DEF = meanFork;
            
        end
        
        function yp = getRespForClusters(this,listIn)
            L = length(this.dayClass);
            yp = [];
            for i = 1:L
                yp = [yp this.dayClass_DEF(listIn(i,:),:)];
            end
            yp = this.desaturate(yp',1);
        end
        
        function this = createClSet(this)
            this = this.kmeansDayClusters(16);
            [md,~] = size(this.dayClass);
            this.y_cl = this.dayClass;
            [~,n] = size(this.X);
            NB = 5-n;
            X_cl_ = zeros([length(this.dayClass),n-1]);
            for i = 1:48:length(this.y_Imp)+1-48
                X_cl_((i+47)/48,:) = [ this.X_Imp(i,2-NB) this.X_Imp(i,4-NB) this.X_Imp(i,5-NB) ];
            end
            this.X_cl = X_cl_;
            
            this.tdd = this.tdimp / length(this.y_Imp) * md;
            this.tmrd = this.tdd + 1;
            
            this.X_cl_train = this.X_cl(1:this.tdd,:);
            this.y_cl_train = this.y_cl(1:this.tdd);
            this.X_cl_test = this.X_cl(this.tmrd:md,:);
            this.y_cl_test = this.y_cl(this.tmrd:md);
        end
        
        function [plotfig,avg_acc] = generateRegPlots(this,startday,nplots,varargin)
            
            figChoice = 'day';
            for i = 1:2:length(varargin)
                if strcmp('PlotType',varargin{i})
                    switch varargin{i+1}
                        case 'daily'
                            figChoice = 'day';
                        case 'weekly'
                            figChoice = 'week';
                            %                         case ''
                    end
                end
            end
            
            persistent fignum;
            if isempty(fignum)
                fignum = 0;
            end
            fignum = fignum + 1;
            
            figttl = [num2str(fignum) ': ' this.ttl];
            accarr = zeros([1,nplots]);
            
            if isa(startday,'datetime')
                startday = datenum(startday);
            end
            
            if startday < this.tomorrow
                fprintf('WARNING: some value predicted may be part of training set')
                figttl = ['(WARNING! Training Data Present!) ',figttl];
            end
            
            if strcmp(figChoice,'day')
                
                idcurr = startday;
                
                plotfig = figure('NumberTitle','off','Name',[figttl,' Daily Plots']);
                
                for i = 1:nplots
                    
                    [dayIdcs,dayLen] = this.getDay(idcurr);
                    acc = 100 * sum(this.level(dayIdcs) == this.level_pred(dayIdcs)) / dayLen;
                    accarr(i) = acc;
                    
                    subplot(ceil(sqrt(nplots)),ceil(sqrt(nplots)),i)
                    hold on
                    
                    plot(this.score(dayIdcs), 'b-')
                    
                    plot(this.score_pred(dayIdcs), 'r--')
                    
                    super_suit = ones(size(this.score(dayIdcs)));
                    lspec = 'g:';
                    plot(20*super_suit,lspec);
                    plot(60*super_suit,lspec);
                    plot(100*super_suit,lspec);
                    plot(140*super_suit,lspec);
                    plot(200*super_suit,lspec);
                    
                    td=0;
                    if(sum(find(this.today==dayIdcs)) ~= 0)
                        xline(dayLen-1,'k-','LineWidth',10)
                        td = 1;
                    end
                    
                    plttl = ...
                        [this.wkdayNames(idcurr,:) ', ' datestr(this.dtArr(idcurr)) ': Acc = '...
                        num2str(acc) '%' ', dayLen = ' num2str(dayLen)];
                    title(plttl)
                    xlabel('observations (~1 per 30 minutes)')
                    ylabel('NEDOC Score')
                    if td
                        legend('Actual','Predictor','NEDOC Levels','Today')
                    elseif i == 1
                        legend('Actual','Predictor','NEDOC Levels')
                    end
                    axis([1, dayLen, 0, 200])
                    
                    hold off
                    
                    idcurr = dayIdcs(dayLen) + 1;
                    
                end
                
            elseif strcmp(figChoice,'week')
                
                [list,~] = this.getWeek(startday);
                idcurr = list(1);
                
                plotfig = figure('NumberTitle','off','Name',[figttl,' Weekly Plots']);
                
                for i = 1:nplots
                    
                    [weekIdcs,weekLen] = this.getWeek(idcurr);
                    acc = 100 * sum(this.level(weekIdcs) == this.level_pred(weekIdcs)) / weekLen;
                    accarr(i) = acc;
                    
                    subplot(ceil(sqrt(nplots)),ceil(sqrt(nplots)),i)
                    hold on
                    
                    plot(this.score(weekIdcs), 'b-')
                    
                    plot(this.score_pred(weekIdcs), 'r--')
                    
                    super_suit = ones(size(this.score(weekIdcs)));
                    lspec = 'g:';
                    plot(20*super_suit,lspec);
                    plot(60*super_suit,lspec);
                    plot(100*super_suit,lspec);
                    plot(140*super_suit,lspec);
                    plot(200*super_suit,lspec);
                    
                    td=0;
                    if(sum(find(this.today==weekIdcs)) ~= 0)
                        xline(weekLen-1,'k-','LineWidth',10)
                        td = 1;
                    end
                    
                    plttl = ...
                        [this.wkdayNames(idcurr,:) ', ' datestr(this.dtArr(idcurr)) ': Acc = '...
                        num2str(acc) '%' ', weekLen = ' num2str(weekLen)];
                    title(plttl)
                    xlabel('observations (~1 per 30 minutes)')
                    ylabel('NEDOC Score')
                    if td
                        legend('Actual','Predictor','NEDOC Levels','Today')
                    else
                        legend('Actual','Predictor','NEDOC Levels')
                    end
                    axis([1, weekLen, 0, 200])
                    
                    hold off
                    
                    idcurr = weekIdcs(weekLen) + 1;
                    
                end
                
            end
            avg_acc = mean(accarr);
        end
        
    end
    
end











