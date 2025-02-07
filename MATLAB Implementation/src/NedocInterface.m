classdef NedocInterface < network_interface
    properties(Access=public)
        % raw data
        table
        dateTime
        date
        
        % params
        PPD
        nObs
        nDays
        trvl_date
        vlts_date
        lag_vector
        PCA_pcnts
        
        % raw matrix forms
        Ym
        Ymp
        
        % transformations
        transforms
        centers
    end
    methods(Access=public)
        function obj = NedocInterface(table,NPPD)
            if nargin == 1
                NPPD = 48;
            end
            obj@network_interface();
            obj.setPPD(table,NPPD);
            
            obj.nObs = height(obj.table);
            obj.nDays = round(obj.nObs/obj.PPD);
            obj.date = DataStruct(unique(obj.table.Date_Time_DTA,'stable'));
            serial_datetime = obj.table.Date + obj.table.Time;
            dateTime_serial_matrix = reshape(serial_datetime,[obj.PPD,obj.nDays])';
            obj.dateTime = datetime(dateTime_serial_matrix,...              floating comment
                'ConvertFrom','datenum','Format','M/d/yyyy,H:mm');
            
            scorevect = obj.table.Score;
            dm = reshape(scorevect,[obj.PPD,obj.nDays])';
            
            obj.Ym = DataStruct(dm);
            obj.Ymp = DataStruct();
            
            obj.centers = {};
            obj.transforms = {};
            obj.lag_vector = 1:14;
            obj.PCA_pcnts = [0.9,0.9];
        end
        function obj = compile(obj,varargin)
            
            trvl = 0.9;
            vlts = 0.9;
            
            for ii=1:2:numel(varargin), key=varargin{ii}; val=varargin{ii+1};
                switch(key)
                    case "Verbose"
                        opts.Verbose = val;
                    case "Plot"
                        if val
                            opts.Plots = "training-progress";
                        else
                            opts.Plots = "none";
                        end
                    case "TrainingSplit"
                        trvl = val;
                    case "ValidationSplit"
                        vlts = val;
                    case "Lags"
                        if numel(val)==1
                            obj.lag_vector = 1:val;
                        else
                            obj.lag_vector = val;
                        end
                    case "PCA"
                        if numel(val)==2
                            obj.PCA_pcnts = val;
                        else
                            error("Invalid entry for PCA")
                        end
                    case "Arch"
                        obj.architecture = val;
                    case "Opts"
                        obj.options = val;
                    otherwise
                        error("varargin key '" + key + "' is invalid")
                end
            end
            
            if gpuDeviceCount() > 0
                opts.ExecutionEnvironment = "gpu";
            else
                opts.ExecutionEnvironment = "cpu";
            end
            
            obj.setsplits(trvl,vlts);
            obj.preprocess();
        end
        function fig = plot(obj,varargin)
            
            datetime_arr = NaT([0,1]);
            dateidx_arr = NaN([0,1]);
            showcost = false;
            
            for i=1:2:numel(varargin), key=varargin{i}; val=varargin{i+1};
                switch key
                    case "DateTimeArray"
                        if isa(val,'string')
                            val = datetime(val);
                        end
                        datetime_arr = val;
                        dateidx_arr = [];
                        for dt = datetime_arr
                            dateidx_arr(end+1) = find(obj.date.all==dt,1); %#ok<AGROW>
                        end
                    case "DateIdxArray"
                        dateidx_arr = val;
                        datetime_arr = obj.date.all(dateidx_arr);
                    case "DateTimeRange"
                        if isa(val,'string')
                            val = datetime(val);
                        end
                        datetime_arr = val(1):caldays(1):val(2);
                        dateidx_arr = [];
                        for dt = datetime_arr
                            dateidx_arr(end+1) = find(obj.date.all==dt,1); %#ok<AGROW>
                        end
                    case "DateIdxRange"
                        dateidx_arr = val(1):val(2);
                        datetime_arr = obj.date.all(dateidx_arr);
                    case "ShowCost"
                        showcost = val;
                    otherwise
                        error("'" + key + "' is not a valid varargin key.");
                end
            end
            if isempty(datetime_arr) || isempty(dateidx_arr)
                error("Error! Must specify dates to plot.")
            end
            
            fig = figure();
            sub_dim = ceil(sqrt(numel(dateidx_arr)));
            if showcost
                costs = obj.getLoss("DateIdxArray",dateidx_arr);
            end
            
            for ii = 1:numel(dateidx_arr), i=dateidx_arr(ii);
                subplot(sub_dim,sub_dim,ii)
                hold on
                plot(obj.dateTime(i,:),obj.Ym.all(i,:))
                plot(obj.dateTime(i,:),obj.Ymp.all(i,:))
                titlestr = datestr(obj.date.all(i));
                if showcost
                    titlestr = titlestr + " : cost=" + num2str(costs(i));
                end
                title(titlestr)
                xlabel("Time")
                ylabel("NEDOC Score")
                ylim([0,300])
                hold off
            end
            
        end
        function obj = assess(obj)
            
        end
        function obj = loadNet(obj,netname,netnum)
            % name of dir is "{netname}_{netnum:leadingZeros}"
            
            name = netname + "_" + num2str(netnum,"%03d");
            fprintf("Loading network, architecture, and options files from: 'mdl/"...
                + name + "'...\t")
            try
                [net,arch,opts] = loadnet(name);
            catch e
                rethrow(e);
            end
            
            obj.network = net;
            obj.architecture = arch;
            obj.options = opts;
            
            fprintf("Done!\n\n")
        end
        function saveNet(obj,netname,netnum)
            %
            % name of dir is "{netname}_{netnum:leadingZeros}"
            %
            
            name = netname + "_" + num2str(netnum,"%03d");
            
            % keep naming conventions
            net = obj.network;
            layers = obj.architecture;
            opts = obj.options;
            
            fl = fullfile(pwd,"mdl",name);
            mkdir(fl);
            
            save(fullfile(fl,"network.mat"),"net");
            save(fullfile(fl,"architecture.mat"),"layers");
            save(fullfile(fl,"options.mat"),"opts");
            
            addpath(fl);
        end
        function [loss,dates] = getLoss(obj,varargin)
            
            datetime_arr = NaT([0,1]);
            dateidx_arr = NaN([0,1]);
            takeMean = false;
            lossfcn = obj.lossFcn;
            
            for i=1:2:numel(varargin), key=varargin{i}; val=varargin{i+1};
                switch key
                    case "DateTimeArray"
                        if isa(val,'string')
                            val = datetime(val);
                        end
                        datetime_arr = val;
                        dateidx_arr = [];
                        for dt = datetime_arr
                            dateidx_arr(end+1) = find(obj.date.all==dt,1); %#ok<AGROW>
                        end
                    case "DateIdxArray"
                        dateidx_arr = val;
                        datetime_arr = obj.date.all(dateidx_arr);
                    case "SetSpec"
                        switch val
                            case "all"
                                datetime_arr = obj.date.all;
                                dateidx_arr = 1:obj.nDays;
                            case "train"
                                idx = find(obj.date.all==obj.trvl_date,1);
                                datetime_arr = obj.date.all(1:idx);
                                dateidx_arr = 1:idx;
                            case "valid"
                                idx1 = find(obj.date.all==obj.trvl_date,1)+1;
                                idx2 = find(obj.date.all==obj.vlts_date,1);
                                datetime_arr = obj.date.all(idx1:idx2);
                                dateidx_arr = idx1:idx2;
                            case "test"
                                idx = find(obj.date.all==obj.vlts_date,1)+1;
                                datetime_arr = obj.date.all(idx:end);
                                dateidx_arr = idx:obj.nDays;
                            otherwise
                                error("'" + val + "' is not a valid set specifier.")
                        end
                    case "TakeMean"
                        takeMean = val;
                    case "LossFcn"
                        lossfcn = val;
                    otherwise
                        error("'" + key + "' is not a valid varargin key.");
                end
            end
            if isempty(datetime_arr) || isempty(dateidx_arr)
                error("Error! Must specify dates to compute loss.")
            end
            
            dates = datetime_arr;
            
            loss = lossfcn(obj.Ym.all(dateidx_arr,:),obj.Ymp.all(dateidx_arr,:));
            
            if takeMean
                loss = mean(loss);
            end
        end
    end
    methods(Access=protected)
        function obj = setPPD(obj,tbl,NPPD)
            baseppd = 288;
            
            if NPPD < 1
                NPPD = 1;
            elseif NPPD > baseppd
                NPPD = baseppd;
            end
            
            rate = round(baseppd / NPPD);
            
            Date_Time_DTA = downsample( tbl.Date_Time_DTA, rate );
            Date_Time = downsample( tbl.Date_Time, rate );
            Date = downsample( tbl.Date, rate );
            Time = downsample( tbl.Time, rate );
            Month = downsample( tbl.Month, rate );
            WKD_Name = downsample( tbl.WKD_Name, rate );
            Weekday = downsample( tbl.Weekday, rate );
            Score = downsample( tbl.Score, rate );
            Level = downsample( tbl.Level, rate );
            
            obj.table = table(Date_Time_DTA, Date_Time, Date, Time,...
                Month, WKD_Name, Weekday, Score, Level); %#ok<CPROPLC>
            obj.PPD = NPPD;
        end
        function obj = preprocess(obj,varargin)
            % this fcn fills Xr & Yr
            % transform and centers sizes
            obj.centers = cell([1,3]);
            obj.transforms = cell([1,2]);
            
            % lag vector
            lag = obj.lag_vector;
            lastvalid = find(obj.date.all==obj.vlts_date);
            nontest = 1:lastvalid;
            omitlag = nontest(max(lag)+1:end);
            lasttrain = find(obj.date.all==obj.trvl_date);
            
            % Xr
            X_proto = lagmatrix(obj.Ym.all,obj.lag_vector);
            obj.centers{1} = struct('mu',mean(X_proto(omitlag,:)),'sig',std(X_proto(omitlag,:)));
            X_proto = (X_proto - obj.centers{1}.mu) ./ obj.centers{1}.sig;
            obj.transforms{1} = PCA(X_proto(omitlag,:),obj.PCA_pcnts(1));
            X_PCAd = X_proto * obj.transforms{1};
            obj.centers{3} = struct('mu',mean(X_PCAd(omitlag,:)),'sig',std(X_PCAd(omitlag,:)));
            X_PCAd = (X_PCAd - obj.centers{3}.mu) ./ obj.centers{3}.sig;
            
            obj.Xr.all = mat2cellR(X_PCAd(lag(end)+1:end,:));
            obj.Xr.train = mat2cellR(X_PCAd(lag(end)+1:lasttrain,:));
            obj.Xr.valid = mat2cellR(X_PCAd(lasttrain+1:lastvalid,:));
            obj.Xr.test = mat2cellR(X_PCAd(lastvalid+1:end,:));
            
            % Yr
            y_proto = obj.Ym.all;
            obj.centers{2} = struct('mu',mean(y_proto),'sig',std(y_proto));
            y_proto = (y_proto - obj.centers{2}.mu) ./ obj.centers{2}.sig;
            obj.transforms{2} = PCA(y_proto(nontest,:),obj.PCA_pcnts(2));
            y_PCAd = y_proto * obj.transforms{2};
            
            obj.Yr.all = y_PCAd(lag(end)+1:end,:);
            obj.Yr.train = y_PCAd(lag(end)+1:lasttrain,:);
            obj.Yr.valid = y_PCAd(lasttrain+1:lastvalid,:);
            obj.Yr.test = y_PCAd(lastvalid+1:end,:);
        end
        function obj = postprocess(obj,varargin)
            set = fieldnames(obj.Yrp);
            for k=1:numel(set)
                yp = obj.Yrp.(set{k});
                if ~isempty(yp)
                    yp = cast(yp,"double");
                    yp = yp * obj.transforms{2}';
                    yp = obj.centers{2}.sig .* yp + obj.centers{2}.mu;
                    if strcmp(set{k},'all') || strcmp(set{k},'train')
                        yp = [zeros([length(obj.lag_vector),obj.PPD]);yp]; %#ok<AGROW>
                    end
                    obj.Ymp.(set{k}) = yp;
                else
                    obj.Ymp.(set{k}) = [];
                end
            end
        end
        function obj = setsplits(obj,trvl,vlts)
            if isa(trvl,'datetime')
                obj.trvl_date = trvl;
                iTV = find(obj.date.all==trvl);
            elseif isa(trvl,'double')
                if 0 <= trvl && trvl <= 1
                    iTV = round(obj.nDays*trvl);
                    obj.trvl_date = obj.date.all(iTV);
                else
                    iTV = trvl;
                    obj.trvl_date = obj.date.all(iTV);
                end
            else
                error("Invalid datatype for trvl argument")
            end
            if isa(vlts,'datetime')
                obj.vlts_date = vlts;
                iVT = find(obj.date.all==vlts);
            elseif isa(vlts,'double')
                if 0 <= vlts && vlts <= 1
                    iVT = round(obj.nDays*vlts);
                    obj.vlts_date = obj.date.all(iVT);
                else
                    iVT = vlts;
                    obj.vlts_date = obj.date.all(vlts);
                end
            else
                error("Invalid datatype for vlts argument")
            end
            
            obj.Ym.setsplits(iTV,iVT);
            obj.date.setsplits(iTV,iVT);
        end
    end
end