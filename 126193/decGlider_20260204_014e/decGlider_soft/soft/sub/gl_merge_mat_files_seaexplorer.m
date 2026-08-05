% ------------------------------------------------------------------------------
% Merge individual mat files into one unique structure and apply consistency
% test and correction to data.
%
% SYNTAX :
% [o_dataStruct] = gl_merge_mat_files_seaexplorer(o_dataStructList)
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
%   10/27/2023 - RNU - creation
% ------------------------------------------------------------------------------
function [o_dataStruct] = gl_merge_mat_files_seaexplorer(o_dataStructList)

% output parameters initialization
o_dataStruct = [];

% variable names added to the .mat structure
global g_decGl_directEgoVarPathName;

% variable names defined in the json deployment file
global g_decGl_gliderVarName;
global g_decGl_egoVarName;
global g_decGl_gliderVarPathName;

% QC flag values
global g_decGl_qcInterpolated;
global g_decGl_qcMissing;

% init dimension of input arrays
NB_COL = 5;
NB_LIG = 10000;


% initialize input arrays
mTimeLabel = [];
mTimeData = nan(NB_LIG, NB_COL);
sTimeLabel = [];
sTimeData = nan(NB_LIG, NB_COL);
gTimeLabel = [];
gTimeData = nan(NB_LIG, NB_COL);

% create the list of glider usefull variables
idF = find(~cellfun(@isempty, g_decGl_gliderVarName));
gliderVarNamList = g_decGl_gliderVarName(idF);
directEgoVarPathName = unique(g_decGl_directEgoVarPathName);
for idV = 1:length(directEgoVarPathName)
   idF = strfind(directEgoVarPathName{idV}, '.');
   gliderVarNamList{end+1} = directEgoVarPathName{idV}(idF(end)+1:end);
end
gliderVarNamList{end+1} = 'm_present_time';
gliderVarNamList{end+1} = 'sci_m_present_time';
gliderVarNamList = unique(gliderVarNamList);

% store input data in dedicated arrays
startId = 1;
lastId = -1;
startId2 = 1;
lastId2 = -1;
for idStruct = 1:length(o_dataStructList)
   rawData = o_dataStructList{idStruct};

   % if time axis is missing, duplicate the existing one
   if (~isempty(rawData.vars_m_time) && isfield(rawData.vars_m_time, 'Timestamp'))
      if (isempty(rawData.vars_sci_time) || (~isempty(rawData.vars_sci_time) && ~isfield(rawData.vars_sci_time, 'PLD_REALTIMECLOCK')))
         rawData.vars_sci_time.PLD_REALTIMECLOCK = rawData.vars_m_time.Timestamp;
      end
   end
   if (~isempty(rawData.vars_sci_time) && isfield(rawData.vars_sci_time, 'PLD_REALTIMECLOCK'))
      if (isempty(rawData.vars_m_time) || (~isempty(rawData.vars_m_time) && ~isfield(rawData.vars_m_time, 'Timestamp')))
         rawData.vars_m_time.Timestamp = rawData.vars_sci_time.PLD_REALTIMECLOCK;
      end
   end

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % vars_m_time & vars_sci_time data
   pathList = [{'vars_m_time'} {'vars_sci_time'}];
   for idP = 1:length(pathList)
      path = pathList{idP};
      if (isempty(rawData.(path)))
         continue
      end
      rawNameList = fields(rawData.(path));
      if (idP == 1)
         fLabel = mTimeLabel;
         fData = mTimeData;
      else
         fLabel = sTimeLabel;
         fData = sTimeData;
      end

      for idN = 1:length(rawNameList)
         name = rawNameList{idN};
         % keep only usefull variables
         if (~any(strcmp(name, gliderVarNamList)))
            continue
         end
         data = rawData.(path).(name);
         while (startId+length(data)-1 > size(fData, 1))
            fData = cat(1, fData, nan(NB_LIG, size(fData, 2)));
         end
         if (startId+length(data)-1 > lastId)
            lastId = startId+length(data)-1;
         end

         idF = find(strcmp(name, fLabel));
         if (isempty(idF))
            fLabel{end+1} = name;
            idF = length(fLabel);
            while (length(fLabel) > size(fData, 2))
               fData = cat(2, fData, nan(size(fData, 1), NB_COL));
            end
         end
         fData(startId:startId+length(data)-1, idF) = double(data');
      end

      if (idP == 1)
         mTimeLabel = fLabel;
         mTimeData = fData;
         if (size(mTimeData, 1) > size(sTimeData, 1))
            sTimeData = cat(1, sTimeData, nan(size(mTimeData, 1)-size(sTimeData, 1), size(sTimeData, 2)));
         end
      else
         sTimeLabel = fLabel;
         sTimeData = fData;
         if (size(sTimeData, 1) > size(mTimeData, 1))
            mTimeData = cat(1, mTimeData, nan(size(sTimeData, 1)-size(mTimeData, 1), size(mTimeData, 2)));
         end
      end
   end
   if (lastId > 0)
      startId = lastId + 1;
      lastId = -1;
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

   clear rawData
end
clear o_dataStructList
mTimeData(startId:end, :) = [];
sTimeData(startId:end, :) = [];
gTimeData(startId2:end, :) = [];
mTimeData(:, length(mTimeLabel)+1:end) = [];
sTimeData(:, length(sTimeLabel)+1:end) = [];
gTimeData(:, length(gTimeLabel)+1:end) = [];

% replace Nan values of rawData.vars_sci_time.sci_m_present_time by
% rawData.vars_m_time.m_present_time values (so that technical data are
% recovered even without sci measurement)
mTime = [];
idMTime = find(strcmp(mTimeLabel, 'Timestamp'));
if (~isempty(idMTime))
   mTime = mTimeData(:, idMTime);
end
sTime = [];
idSTime = find(strcmp(sTimeLabel, 'PLD_REALTIMECLOCK'));
if (~isempty(idSTime))
   sTime = sTimeData(:, idSTime);
end
if (~isempty(mTime) && ~isempty(sTime))
   idNan = find(isnan(mTime));
   mTimeData(idNan, idMTime) = sTime(idNan);
   idNan = find(isnan(sTime));
   sTimeData(idNan, idSTime) = mTime(idNan);
end

% clean measurements (delete timestamps when all measurements == Nan)
dataAll1 = mTimeData;
dataAll2 = sTimeData;
if (~isempty(idMTime))
   dataAll1(:, idMTime) = [];
end
if (~isempty(idSTime))
   dataAll2(:, idSTime) = [];
end
dataAll = [dataAll1 dataAll2];
idDel = find(sum(isnan(dataAll), 1) == size(dataAll, 1));
% add lines where time is nan
timeGliderVarName = g_decGl_gliderVarPathName{find(strcmp(g_decGl_egoVarName, 'TIME'))};
idF = strfind(timeGliderVarName, '.');
timeGliderVarName = timeGliderVarName(idF(end)+1:end);
time = [];
idTime = find(strcmp(mTimeLabel, timeGliderVarName));
if (~isempty(idTime))
   time = mTimeData(:, idTime);
else
   idTime = find(strcmp(sTimeLabel, timeGliderVarName));
   if (~isempty(idTime))
      time = sTimeData(:, idTime);
   end
end
idDel = unique([idDel find(isnan(time))]);
mTimeData(idDel, :) = [];
sTimeData(idDel, :) = [];

% set data in chronological order
pathList = [{'vars_m_time'} {'vars_sci_time'} {'vars_time_gps'}];
timeList = [{'Timestamp'} {'PLD_REALTIMECLOCK'} {'time'}];
for idP = 1:length(pathList)
   if (idP == 1)
      fLabel = mTimeLabel;
      fData = mTimeData;
   elseif (idP == 2)
      fLabel = sTimeLabel;
      fData = sTimeData;
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
   elseif (idP == 2)
      sTimeData = fData;
   else
      gTimeData = fData;
   end
end

% remove test measurements
idTime = find(strcmp(mTimeLabel, 'Timestamp'));
timeData = mTimeData(:, idTime);
idF = find(diff(timeData) > 365*86400/2);
if (length(idF) == 1)
   fprintf('INFO: Deleting the %d first measurements (dated %s to %s while next one is dated %s', ...
      idF, ...
      gl_julian_2_gregorian(gl_epoch_2_julian(timeData(1))), ...
      gl_julian_2_gregorian(gl_epoch_2_julian(timeData(idF))), ...
      gl_julian_2_gregorian(gl_epoch_2_julian(timeData(idF+1))));

   mTimeData(1:idF, :) = [];
   sTimeData(1:idF, :) = [];
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
   idTime = find(strcmp(timeGliderVarName, sTimeLabel));
   if (~isempty(idTime))
      time = sTimeData(:, idTime);
   else
      idTime = find(strcmp(timeGliderVarName, mTimeLabel));
      time = mTimeData(:, idTime);
   end
   pres = [];
   idPres = find(strcmp(presGliderVarName, sTimeLabel));
   if (~isempty(idPres))
      pres = sTimeData(:, idPres);
   else
      idPres = find(strcmp(presGliderVarName, mTimeLabel));
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

      idPres = find(strcmp(presGliderVarName, sTimeLabel));
      if (~isempty(idPres))
         sTimeData(:, idPres) = pres;
      else
         idPres = find(strcmp(presGliderVarName, mTimeLabel));
         mTimeData(:, idPres) = pres;
      end
      if (~isempty(presQcGliderVarName))
         idPresQc = find(strcmp(presQcGliderVarName, sTimeLabel));
         if (~isempty(idPresQc))
            sTimeData(:, idPresQc) = pres_qc;
         else
            idPresQc = find(strcmp(presQcGliderVarName, mTimeLabel));
            mTimeData(:, idPresQc) = pres_qc;
         end
      else
         idPres = find(strcmp(presGliderVarName, sTimeLabel));
         if (~isempty(idPres))
            sTimeLabel{end+1} = 'PRES_QC';
            sTimeData = cat(2, sTimeData, nan(size(sTimeData, 1), 1));
            sTimeData(:, end) = pres_qc;
            g_decGl_directEgoVarPathName{end+1} = 'vars_sci_time.PRES_QC';
         else
            mTimeLabel{end+1} = 'PRES_QC';
            mTimeData = cat(2, mTimeData, nan(size(mTimeData, 1), 1));
            mTimeData(:, end) = pres_qc;
            g_decGl_directEgoVarPathName{end+1} = 'vars_m_time.PRES_QC';
         end
      end
   end
end

% fill the output structure
rawData = struct( ...
   'vars_m_time', [], ...
   'vars_sci_time', [], ...
   'vars_time_gps', []);

pathList = [{'vars_m_time'} {'vars_sci_time'} {'vars_time_gps'}];
for idP = 1:length(pathList)
   path = pathList{idP};
   if (idP == 1)
      fLabel = mTimeLabel;
      fData = mTimeData;
   elseif (idP == 2)
      fLabel = sTimeLabel;
      fData = sTimeData;
   else
      fLabel = gTimeLabel;
      fData = gTimeData;
   end
   for idN = 1:length(fLabel)
      rawData.(path).(fLabel{idN}) = fData(:, idN);
   end
end

o_dataStruct = rawData;

return
