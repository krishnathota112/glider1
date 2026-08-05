% ------------------------------------------------------------------------------
% Merge individual mat files into one unique structure and apply consistency
% test and correction to data.
%
% SYNTAX :
% [o_dataStruct] = gl_merge_mat_files_seaglider(o_dataStructList)
%
% INPUT PARAMETERS :
%   o_dataStructList : list of individual Yo data structures
%
% OUTPUT PARAMETERS :
%   o_dataStruct : output merged data structure
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   10/31/2023 - RNU - creation
% ------------------------------------------------------------------------------
function [o_dataStruct] = gl_merge_mat_files_seaglider(o_dataStructList)

% output parameters initialization
o_dataStruct = [];

% variable names added to the .mat structure
global g_decGl_directEgoVarPathName;

% variable names defined in the json deployment file
global g_decGl_gliderVarName;
global g_decGl_gliderAdjVarName;
global g_decGl_egoVarName;

% QC flag values
global g_decGl_qcInterpolated;
global g_decGl_qcMissing;

% init dimension of input arrays
NB_COL = 5;
NB_LIG = 10000;


% initialize input arrays
mTimeLabel = [];
mTimeData = nan(NB_LIG, NB_COL);
gTimeLabel = [];
gTimeData = nan(NB_LIG, NB_COL);

% create the list of glider usefull variables
idF = find(~cellfun(@isempty, g_decGl_gliderVarName));
gliderVarNamList = g_decGl_gliderVarName(idF);
idF = find(~cellfun(@isempty, g_decGl_gliderAdjVarName));
gliderVarNamList = [gliderVarNamList g_decGl_gliderAdjVarName(idF)];
directEgoVarPathName = unique(g_decGl_directEgoVarPathName);
for idV = 1:length(directEgoVarPathName)
   idF = strfind(directEgoVarPathName{idV}, '.');
   gliderVarNamList{end+1} = directEgoVarPathName{idV}(idF(end)+1:end);
end
gliderVarNamList{end+1} = 'm_present_time';
gliderVarNamList{end+1} = 'sci_m_present_time';
gliderVarNamList = unique(gliderVarNamList);

% find the glider variable names for TIME, LATITUDE, LONGITUDE, PRES, TIME_GPS,
% LATITUDE_GPS and LONGITUDE_GPS
timeGliderVarName = g_decGl_gliderVarName{find(strcmp(g_decGl_egoVarName, 'TIME'))};
latGliderVarName = g_decGl_gliderVarName{find(strcmp(g_decGl_egoVarName, 'LATITUDE'))};
lonGliderVarName = g_decGl_gliderVarName{find(strcmp(g_decGl_egoVarName, 'LONGITUDE'))};
presGliderVarName = [];
idPres = find(strcmp(g_decGl_egoVarName, 'PRES'));
if (~isempty(idPres))
   presGliderVarName = g_decGl_gliderVarName{idPres};
end
timeGpsGliderVarName = g_decGl_gliderVarName{find(strcmp(g_decGl_egoVarName, 'TIME_GPS'))};
latGpsGliderVarName = g_decGl_gliderVarName{find(strcmp(g_decGl_egoVarName, 'LATITUDE_GPS'))};
lonGpsGliderVarName = g_decGl_gliderVarName{find(strcmp(g_decGl_egoVarName, 'LONGITUDE_GPS'))};

% store input data in dedicated arrays
startId = 1;
lastId = -1;
startId2 = 1;
lastId2 = -1;
currentDataAll = [];
currentFields = [];
for idStruct = 1:length(o_dataStructList)
   rawData = o_dataStructList{idStruct};

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % vars_time data
   if (~isempty(rawData.vars_time))
      rawNameList = fields(rawData.vars_time);
      for idN = 1:length(rawNameList)
         name = rawNameList{idN};
         % keep only usefull variables
         if (~any(strcmp(name, gliderVarNamList)))
            continue
         end
         data = rawData.vars_time.(name);
         while (startId+length(data)-1 > size(mTimeData, 1))
            mTimeData = cat(1, mTimeData, nan(NB_LIG, size(mTimeData, 2)));
         end
         if (startId+length(data)-1 > lastId)
            lastId = startId+length(data)-1;
         end

         idF = find(strcmp(name, mTimeLabel));
         if (isempty(idF))
            mTimeLabel{end+1} = name;
            idF = length(mTimeLabel);
            while (length(mTimeLabel) > size(mTimeData, 2))
               mTimeData = cat(2, mTimeData, nan(size(mTimeData, 1), NB_COL));
            end
         end
         mTimeData(startId:startId+length(data)-1, idF) = double(data');
      end
      if (lastId > 0)
         startId = lastId + 1;
         lastId = -1;
      end
   end

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % vars_time_gps data
   if (~isempty(rawData.vars_time_gps))
      rawNameList = fields(rawData.vars_time_gps);
      for idN = 1:length(rawNameList)
         name = rawNameList{idN};
         data = rawData.vars_time_gps.(name);
         while (startId2+length(data)-1 > size(gTimeData, 1))
            gTimeData = cat(1, gTimeData, nan(NB_LIG, size(gTimeData, 2)));
         end
         if (startId2+length(data)-1 > lastId2)
            lastId2 = startId2+length(data)-1;
         end

         idF = find(strcmp(name, gTimeLabel));
         if (isempty(idF))
            gTimeLabel{end+1} = name;
            idF = length(gTimeLabel);
            while (length(gTimeLabel) > size(gTimeData, 2))
               gTimeData = cat(2, gTimeData, nan(size(gTimeData, 1), NB_COL));
            end
         end
         gTimeData(startId2:startId2+length(data)-1, idF) = double(data');
      end
      if (lastId2 > 0)
         startId2 = lastId2 + 1;
         lastId2 = -1;
      end
   end

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % current data
   if (isfield(rawData, 'current'))
      if (~isempty(rawData.current))

         % add time and location information for subsurface and surface current
         % estimates
         rawData.current.time = [];
         rawData.current.latitude = [];
         rawData.current.longitude = [];
         rawData.current.meanDepth = [];
         rawData.current.timeGps = [];
         rawData.current.latitudeGps = [];
         rawData.current.longitudeGps = [];
         if (isfield(rawData.current, 'depth_avg_curr_qc') && ...
               isfield(rawData.vars_time, timeGliderVarName) && ...
               isfield(rawData.vars_time, latGliderVarName) && ...
               isfield(rawData.vars_time, lonGliderVarName))
            timeVal = rawData.vars_time.(timeGliderVarName);
            latVal = rawData.vars_time.(latGliderVarName);
            lonVal = rawData.vars_time.(lonGliderVarName);
            idNoNan = find(~isnan(timeVal) & ~isnan(latVal) & ~isnan(lonVal));
            if (~isempty(idNoNan))
               timeVal = timeVal(idNoNan);
               latVal = latVal(idNoNan);
               lonVal = lonVal(idNoNan);
               % the subsurface current location is assigned to the median time value
               % of the available location times
               timeCurrent = median(timeVal);
               [~, minId] = min(abs(timeVal-timeCurrent));
               rawData.current.time = timeCurrent;
               rawData.current.latitude = latVal(minId);
               rawData.current.longitude = lonVal(minId);
               % the subsurface depth is assigned to the mean of, available pres
               % values
               if (~isempty(presGliderVarName) && isfield(rawData.vars_time, presGliderVarName))
                  presVal = rawData.vars_time.(presGliderVarName);
                  presVal(isnan(presVal)) = [];
                  rawData.current.meanDepth = mean(presVal);
               end
            else
               fprintf('ERROR: Cannot find subsurface location to assign to the subsurface current estimate\n');
            end
         end
         if (isfield(rawData.current, 'surface_curr_qc') && ...
               isfield(rawData.vars_time, timeGliderVarName) && ...
               isfield(rawData.vars_time_gps, timeGpsGliderVarName) && ...
               isfield(rawData.vars_time_gps, latGpsGliderVarName) && ...
               isfield(rawData.vars_time_gps, lonGpsGliderVarName))
            timeVal = rawData.vars_time.(timeGliderVarName);
            timeVal(isnan(timeVal)) = [];
            timeGpsVal = rawData.vars_time_gps.(timeGpsGliderVarName);
            latGpsVal = rawData.vars_time_gps.(latGpsGliderVarName);
            lonGpsVal = rawData.vars_time_gps.(lonGliderVarName);
            idNoNan = find(~isnan(timeGpsVal) & ~isnan(latGpsVal) & ~isnan(lonGpsVal));
            timeGpsVal = timeGpsVal(idNoNan);
            latGpsVal = latGpsVal(idNoNan);
            lonGpsVal = lonGpsVal(idNoNan);
            [~, idSort] = sort(timeGpsVal);
            timeGpsVal = timeGpsVal(idSort);
            latGpsVal = latGpsVal(idSort);
            lonGpsVal = lonGpsVal(idSort);
            % we store min/max subsurface times to look for surface GPS location
            % (to be assigned to surface current estimate) when it was not
            % provided in the current file
            rawData.current.minTimeForTimeGps = nan;
            rawData.current.maxTimeForTimeGps = nan;
            if (~isempty(timeVal))
               rawData.current.minTimeForTimeGps = min(timeVal);
               rawData.current.maxTimeForTimeGps = max(timeVal);
            end
            % we assign the surface current to the first GPS location that follows
            % the measurement timeseries
            rawData.current.timeGps = nan;
            rawData.current.latitudeGps = nan;
            rawData.current.longitudeGps = nan;
            idSurfCurrent = find(timeGpsVal >= max(timeVal), 1, 'first');
            if (~isempty(idSurfCurrent))
               rawData.current.timeGps = timeGpsVal(idSurfCurrent);
               rawData.current.latitudeGps = latGpsVal(idSurfCurrent);
               rawData.current.longitudeGps = lonGpsVal(idSurfCurrent);
            end
         end

         % store current data
         currentFields = unique([currentFields; fields(rawData.current)]);
         currentDataAll{end+1} = rawData.current;
      end
   end

   clear rawData
end
clear o_dataStructList
mTimeData(startId:end, :) = [];
gTimeData(startId2:end, :) = [];
mTimeData(:, length(mTimeLabel)+1:end) = [];
gTimeData(:, length(gTimeLabel)+1:end) = [];

% set data in chronological order
timeList = [{timeGliderVarName} {timeGpsGliderVarName}];
for idP = 1:length(timeList)
   if (idP == 1)
      fLabel = mTimeLabel;
      fData = mTimeData;
   else
      fLabel = gTimeLabel;
      fData = gTimeData;
   end

   idTime = find(strcmp(fLabel, timeList{idP}));
   [~, idSort] = sort(fData(:, idTime));
   if (any(diff(idSort) ~= 1))
      fData = fData(idSort, :);
   end

   if (idP == 1)
      mTimeData = fData;
   else
      gTimeData = fData;
   end
end

% remove test measurements
idTime = find(strcmp(mTimeLabel, timeGliderVarName));
timeData = mTimeData(:, idTime);
idF = find(diff(timeData) > 365/2);
if (length(idF) == 1)
   fprintf('INFO: Deleting the %d first measurements (dated %s to %s while next one is dated %s', ...
      idF, ...
      gl_julian_2_gregorian(gl_epoch_2_julian(timeData(1))), ...
      gl_julian_2_gregorian(gl_epoch_2_julian(timeData(idF))), ...
      gl_julian_2_gregorian(gl_epoch_2_julian(timeData(idF+1))));

   mTimeData(1:idF, :) = [];
end

% interpolate PRES measurements for all timestamps => needed for PHASE processing

% find the glider variable names for TIME, PRES and PRES_QC
timeGliderVarName = g_decGl_gliderVarName{find(strcmp(g_decGl_egoVarName, 'TIME'))};
presGliderVarName = [];
idPres = find(strcmp(g_decGl_egoVarName, 'PRES'));
if (~isempty(idPres))
   presGliderVarName = g_decGl_gliderVarName{idPres};
end
presQcGliderVarName = [];
idPresQc = find(strcmp(g_decGl_egoVarName, 'PRES_QC'));
if (~isempty(idPresQc))
   presQcGliderVarName = g_decGl_gliderVarName{idPresQc};
end

% convert and interpolate PRES measurements
if (~isempty(timeGliderVarName) && ~isempty(presGliderVarName))

   time = [];
   idTime = find(strcmp(timeGliderVarName, mTimeLabel));
   if (~isempty(idTime))
      time = mTimeData(:, idTime);
   end
   pres = [];
   idPres = find(strcmp(presGliderVarName, mTimeLabel));
   if (~isempty(idPres))
      pres = mTimeData(:, idPres);
   end

   if (~isempty(time) && ~isempty(pres))

      pres_qc = zeros(1, length(pres));

      idNan = find(isnan(pres));
      if (~isempty(idNan))
         idNotNan = setdiff(1:length(pres), idNan);
         if (length(idNotNan) > 1)
            pres(idNan) = interp1q(time(idNotNan), pres(idNotNan), time(idNan));
            pres_qc(idNan) = g_decGl_qcInterpolated;
            pres_qc(find(isnan(pres))) = g_decGl_qcMissing;
         end
      end

      mTimeData(:, idPres) = pres;
      if (~isempty(presQcGliderVarName))
         idPresQc = find(strcmp(presQcGliderVarName, mTimeLabel));
         if (~isempty(idPresQc))
            mTimeData(:, idPresQc) = pres_qc;
         end
      else
         mTimeLabel{end+1} = 'PRES_QC';
         mTimeData = cat(2, mTimeData, nan(size(mTimeData, 1), 1));
         mTimeData(:, end) = pres_qc;
         g_decGl_directEgoVarPathName{end+1} = 'vars_m_time.PRES_QC';
      end
   end
end

% uniformize current data
varsCurrentStruct = [];
if (~isempty(currentDataAll))
   for id = 1:length(currentFields)
      varsCurrentStruct.(currentFields{id}) = [];
   end
   for idD = 1:length(currentDataAll)
      currentData = currentDataAll{idD};
      for id = 1:length(currentFields)
         if (isfield(currentData, currentFields{id}))
            value = currentData.(currentFields{id});
         else
            value = nan;
         end
         varsCurrentStruct.(currentFields{id}) = [varsCurrentStruct.(currentFields{id}); value];
      end
   end
end

% fill the output structure
rawData = struct( ...
   'vars_time', [], ...
   'vars_time_gps', [], ...
   'vars_current', varsCurrentStruct);

pathList = [{'vars_time'} {'vars_time_gps'}];
for idP = 1:length(pathList)
   path = pathList{idP};
   if (idP == 1)
      fLabel = mTimeLabel;
      fData = mTimeData;
   else
      fLabel = gTimeLabel;
      fData = gTimeData;
   end
   for idN = 1:length(fLabel)
      rawData.(path).(fLabel{idN}) = fData(:, idN);
   end
end

% assign remaining GPS location to surface current estimate
if (~isempty(rawData.vars_current))
   % using existing ones
   timeIdList = find(isnan(rawData.vars_current.timeGps));
   for idT = timeIdList'
      if (idT < length(rawData.vars_current.timeGps))
         idSurfCurrent = find((rawData.vars_time_gps.time >= rawData.vars_current.maxTimeForTimeGps(idT)) & ...
            (rawData.vars_time_gps.time <= rawData.vars_current.minTimeForTimeGps(idT+1)), 1, 'first');
      else
         idSurfCurrent = find(rawData.vars_time_gps.time >= rawData.vars_current.maxTimeForTimeGps(idT), 1, 'first');
      end
      if (~isempty(idSurfCurrent))
         rawData.vars_current.timeGps(idT) = rawData.vars_time_gps.time(idSurfCurrent);
         rawData.vars_current.latitudeGps(idT) = rawData.vars_time_gps.latitude(idSurfCurrent);
         rawData.vars_current.longitudeGps(idT) = rawData.vars_time_gps.longitude(idSurfCurrent);
      end
   end
   % interpolating existing ones
   if (any(isnan(rawData.vars_current.timeGps)))
      timeGps = rawData.vars_time_gps.time;
      latGps = rawData.vars_time_gps.latitude;
      lonGps = rawData.vars_time_gps.longitude;
      idDel = find(isnan(timeGps) | isnan(latGps) | isnan(lonGps));
      timeGps(idDel) = [];
      latGps(idDel) = [];
      lonGps(idDel) = [];
      if (length(timeGps) > 1)
         timeIdList = find(isnan(rawData.vars_current.timeGps));
         for idT = timeIdList'
            latInterp = interp1q(timeGps, latGps, rawData.vars_current.maxTimeForTimeGps(idT));
            lonInterp = interp1q(timeGps, lonGps, rawData.vars_current.maxTimeForTimeGps(idT));
            if (~isnan(latInterp) && ~isnan(lonInterp))
               rawData.vars_current.timeGps(idT) = rawData.vars_current.maxTimeForTimeGps(idT);
               rawData.vars_current.latitudeGps(idT) = latInterp;
               rawData.vars_current.longitudeGps(idT) = lonInterp;
            else
               fprintf('WARNING: Cannot find a GPS location to assign to the surface current estimate\n');
            end
         end
      end
   end
end

o_dataStruct = rawData;

return
